import SwiftUI
import MapKit
import CoreLocation

struct SightingMapView: View {
    @StateObject private var vm = SightingMapViewModel()
    @State private var selectedSighting: Sighting?
    @State private var selectedGroup: SightingGroup?
    @State private var showSaved = false
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
                    ForEach(SightingGroup.grouping(vm.sightings)) { group in
                        Annotation(
                            group.sightings.count > 1
                                ? "\(group.sightings.count) sightings"
                                : (group.sightings[0].displaySpecies ?? "Unknown"),
                            coordinate: group.coordinate
                        ) {
                            groupPin(group)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSaved = true
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel("Saved sightings")
                }
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
            .sheet(item: $selectedGroup) { group in
                SightingListView(title: "\(group.sightings.count) sightings here", sightings: group.sightings)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSaved) {
                SavedSightingsView()
                    .presentationDetents([.medium, .large])
            }
            .task {
                vm.requestLocationPermission()
                await vm.load()
            }
        }
    }

    /// One pin per place. A place with a single sighting opens it directly; a
    /// place with several opens a list to choose from — replaces the old
    /// approach of fanning overlapping pins out into a circle.
    private func groupPin(_ group: SightingGroup) -> some View {
        let count = group.sightings.count
        let annotated = group.sightings.contains { $0.annotationCount > 0 }
        return Button {
            if count == 1 { selectedSighting = group.sightings[0] } else { selectedGroup = group }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        count > 1
                            ? AnyShapeStyle(Color.indigo.gradient)
                            : annotated
                                ? AnyShapeStyle(Color.teal.gradient)
                                : AnyShapeStyle(Color.orange.gradient)
                    )
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 3)

                Image(systemName: "mappin")
                    .foregroundStyle(.white)
                    .font(.system(size: 17, weight: .semibold))

                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.indigo)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 2)
                        .background(.white, in: Capsule())
                        .overlay(Capsule().stroke(Color.indigo, lineWidth: 1.5))
                        .offset(x: 14, y: -14)
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
