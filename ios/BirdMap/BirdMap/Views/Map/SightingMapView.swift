import SwiftUI
import MapKit
import CoreLocation

struct SightingMapView: View {
    @StateObject private var vm = SightingMapViewModel()
    @State private var selectedSighting: Sighting?
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
        )
    )

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                ForEach(vm.sightings) { sighting in
                    Annotation(
                        sighting.topSpecies ?? sighting.aiSpeciesSuggestion ?? "Unknown Bird",
                        coordinate: CLLocationCoordinate2D(
                            latitude: sighting.latitude,
                            longitude: sighting.longitude
                        )
                    ) {
                        Button {
                            selectedSighting = sighting
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.teal.opacity(0.85))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "bird.fill")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 14))
                            }
                        }
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .navigationTitle("Bird Sightings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.isLoading {
                        ProgressView()
                    } else {
                        Button { Task { await vm.load() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(item: $selectedSighting) { sighting in
                SightingDetailView(sightingID: sighting.id)
            }
            .task { await vm.load() }
            .onMapCameraChange(frequency: .onEnd) { ctx in
                // Debounce: cancel any pending region fetch and wait 600ms before
                // firing a new one. Rapid pans/zooms won't each trigger a network
                // request, reducing unnecessary radio activations.
                vm.scheduleRegionLoad(ctx.region)
            }
        }
    }
}

@MainActor
final class SightingMapViewModel: ObservableObject {
    @Published var sightings: [Sighting] = []
    @Published var isLoading = false

    private var debounceTask: Task<Void, Never>?

    func load() async {
        isLoading = true
        sightings = (try? await APIClient.shared.sightings()) ?? []
        isLoading = false
    }

    func scheduleRegionLoad(_ region: MKCoordinateRegion) {
        debounceTask?.cancel()
        debounceTask = Task {
            // 600ms debounce — waits for the user to stop moving the map
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
        sightings = (try? await APIClient.shared.sightings(bbox: (
            minLat: lat - dLat, maxLat: lat + dLat,
            minLng: lng - dLng, maxLng: lng + dLng
        ))) ?? []
    }
}
