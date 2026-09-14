import SwiftUI
import MapKit
import CoreLocation

struct SightingMapView: View {
    @StateObject private var vm = SightingMapViewModel()
    @State private var selectedSighting: Sighting?
    @State private var cameraPosition = MapCameraPosition.userLocation(fallback: .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
        )
    ))

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    UserAnnotation {
                        // Plain dot instead of MapKit's default marker, which
                        // draws a heading cone (a triangular wedge) whenever
                        // the device has a compass fix — not configurable
                        // any other way on the built-in marker.
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    }
                    ForEach(displayPositions) { positioned in
                        Annotation(
                            positioned.sighting.topSpecies ?? positioned.sighting.aiSpeciesSuggestion ?? "Unknown",
                            coordinate: positioned.coordinate
                        ) {
                            sightingPin(positioned.sighting)
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapScaleView()
                }
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    vm.scheduleRegionLoad(ctx.region)
                }

                if vm.isLoading {
                    loadingBadge
                } else if !vm.sightings.isEmpty {
                    countBadge
                }
            }
            .navigationTitle("Bird Sightings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isLoading)
                }
            }
            .sheet(item: $selectedSighting) { sighting in
                SightingDetailView(sightingID: sighting.id ?? "")
                    .presentationDetents([.medium, .large])
            }
            .task {
                vm.requestLocationPermission()
                await vm.load()
            }
        }
    }

    /// Sightings reported at (or very near) the same spot would otherwise
    /// render as fully overlapping annotations with only the top one
    /// tappable. Groups sightings within ~1m of each other and, for any
    /// group larger than one, fans them out in a small circle around the
    /// shared point — display-only, doesn't touch the stored coordinates.
    private var displayPositions: [PositionedSighting] {
        var groups: [String: [Sighting]] = [:]
        for sighting in vm.sightings {
            // ~5 decimal places of lat/lng is ~1m precision — close enough
            // to count as "the same spot" for pin-overlap purposes.
            let key = "\(Int((sighting.latitude * 100_000).rounded())),\(Int((sighting.longitude * 100_000).rounded()))"
            groups[key, default: []].append(sighting)
        }

        var result: [PositionedSighting] = []
        for group in groups.values {
            if group.count == 1 {
                let sighting = group[0]
                result.append(PositionedSighting(
                    sighting: sighting,
                    coordinate: CLLocationCoordinate2D(latitude: sighting.latitude, longitude: sighting.longitude)
                ))
            } else {
                // ~0.00012deg latitude is roughly 13m — enough separation to
                // be individually tappable at typical zoom without drifting
                // the pins far from their real location.
                let radius = 0.00012
                let latRadians = group[0].latitude * .pi / 180
                for (index, sighting) in group.enumerated() {
                    let angle = (2 * .pi / Double(group.count)) * Double(index)
                    let dLat = radius * cos(angle)
                    let dLng = (radius * sin(angle)) / max(cos(latRadians), 0.01)
                    result.append(PositionedSighting(
                        sighting: sighting,
                        coordinate: CLLocationCoordinate2D(
                            latitude: sighting.latitude + dLat,
                            longitude: sighting.longitude + dLng
                        )
                    ))
                }
            }
        }
        return result
    }

    private func sightingPin(_ sighting: Sighting) -> some View {
        Button {
            selectedSighting = sighting
        } label: {
            ZStack {
                Circle()
                    .fill(
                        sighting.isAudio
                            ? AnyShapeStyle(Color.indigo.gradient)
                            : sighting.annotationCount > 0
                                ? AnyShapeStyle(Color.teal.gradient)
                                : AnyShapeStyle(Color.orange.gradient)
                    )
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 3)

                Image(systemName: sighting.isAudio ? "mic.fill" : "camera.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .semibold))

                if sighting.annotationCount > 0 {
                    Text("\(sighting.annotationCount)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.green.gradient, in: Circle())
                        .offset(x: 13, y: -13)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var countBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "binoculars.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.caption)
            Text("\(vm.sightings.count) sighting\(vm.sightings.count == 1 ? "" : "s") in view")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 14)
    }

    private var loadingBadge: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.8)
            Text("Loading sightings…")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 14)
    }
}

private struct PositionedSighting: Identifiable {
    let sighting: Sighting
    let coordinate: CLLocationCoordinate2D
    var id: String { sighting.id ?? "\(coordinate.latitude),\(coordinate.longitude)" }
}

@MainActor
final class SightingMapViewModel: ObservableObject {
    @Published var sightings: [Sighting] = []
    @Published var isLoading = false

    private var debounceTask: Task<Void, Never>?
    private let locationManager = CLLocationManager()

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func load() async {
        isLoading = true
        // Keep whatever's already on screen if this fails (transient network
        // errors shouldn't blank out the map) — only replace on success.
        if let result = try? await FirebaseService.shared.fetchSightings() {
            sightings = result
        }
        isLoading = false
    }

    func scheduleRegionLoad(_ region: MKCoordinateRegion) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await loadForRegion(region)
        }
    }

    private func loadForRegion(_ region: MKCoordinateRegion) async {
        let lat = region.center.latitude
        let lng = region.center.longitude
        let dLat = region.span.latitudeDelta / 2
        let dLng = region.span.longitudeDelta / 2
        if let result = try? await FirebaseService.shared.fetchSightings(region: (
            minLat: lat - dLat, maxLat: lat + dLat,
            minLng: lng - dLng, maxLng: lng + dLng
        )) {
            sightings = result
        }
    }
}
