import SwiftUI
import MapKit
import CoreLocation

struct SightingMapView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var vm = SightingMapViewModel()
    @State private var selectedSighting: Sighting?
    @State private var selectedGroup: SightingGroup?
    @State private var showSaved = false
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var placeResults: [MKMapItem] = []
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
                        let c = ThemeColors(scheme: scheme)
                        Circle()
                            .fill(c.clay)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(c.paper, lineWidth: 2.5))
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
            .searchable(text: $searchText, isPresented: $isSearching,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search species, notes, users or places")
            .searchSuggestions { searchSuggestions }
            .task(id: searchText) { await refreshPlaceResults() }
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

    // MARK: - Search

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Sightings whose species, notes or reporter match the query. Searches the
    /// full recently-loaded set rather than only the pins currently in view, so
    /// a match can be anywhere on the map.
    private var sightingMatches: [Sighting] {
        let query = trimmedQuery
        guard query.count >= 2 else { return [] }
        return Array(vm.allSightings.filter { sighting in
            [sighting.displaySpecies, sighting.aiSpeciesSuggestion, sighting.notes, sighting.username]
                .compactMap { $0 }
                .contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }.prefix(8))
    }

    @ViewBuilder
    private var searchSuggestions: some View {
        if trimmedQuery.count < 2 {
            Text("Type a species, a note, a username or a place")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            let matches = sightingMatches
            if !matches.isEmpty {
                Section("Sightings") {
                    ForEach(matches) { sighting in
                        Button { open(sighting) } label: { SightingRow(sighting: sighting) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if !placeResults.isEmpty {
                Section("Places") {
                    ForEach(placeResults, id: \.self) { item in
                        Button { jump(to: item) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Place")
                                    if let subtitle = item.placemark.title, subtitle != item.name {
                                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            } icon: {
                                Image(systemName: "mappin.and.ellipse").foregroundStyle(ThemeColors(scheme: scheme).clay)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if matches.isEmpty && placeResults.isEmpty {
                Text("No sightings or places match \u{201C}\(trimmedQuery)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func finishSearch() {
        isSearching = false
        searchText = ""
        placeResults = []
    }

    private func open(_ sighting: Sighting) {
        finishSearch()
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: sighting.latitude, longitude: sighting.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
        // Several sightings at that spot -> pick from the list; one -> open it.
        let group = SightingGroup.grouping(vm.allSightings)
            .first { $0.sightings.contains { $0.id == sighting.id } }
        if let group, group.sightings.count > 1 {
            selectedGroup = group
        } else {
            selectedSighting = sighting
        }
    }

    private func jump(to item: MKMapItem) {
        finishSearch()
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: item.placemark.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
    }

    private func refreshPlaceResults() async {
        let query = trimmedQuery
        guard query.count >= 3 else { placeResults = []; return }
        try? await Task.sleep(for: .milliseconds(350))      // debounce typing; cancelled by task(id:)
        guard !Task.isCancelled else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try? await MKLocalSearch(request: request).start()
        guard !Task.isCancelled else { return }
        placeResults = Array((response?.mapItems ?? []).prefix(4))
    }

    /// One pin per place. A place with a single sighting opens it directly; a
    /// place with several opens a list to choose from — replaces the old
    /// approach of fanning overlapping pins out into a circle.
    private func groupPin(_ group: SightingGroup) -> some View {
        let count = group.sightings.count
        let c = ThemeColors(scheme: scheme)
        return Button {
            if count == 1 { selectedSighting = group.sightings[0] } else { selectedGroup = group }
        } label: {
            ZStack {
                MapPinShape()
                    .fill(c.clay)
                    .overlay(MapPinShape().stroke(c.ink, lineWidth: 1.6))
                    .frame(width: 30, height: 40)
                Circle()
                    .fill(c.paper)
                    .frame(width: 11, height: 11)
                    .offset(y: -9)

                if count > 1 {
                    Text("\(count)")
                        .font(Theme.sansSemibold(13))
                        .foregroundStyle(c.paper)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(c.ink, in: Circle())
                        .offset(x: 15, y: -20)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var countBadge: some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(spacing: 6) {
            Circle().fill(c.clay).frame(width: 7, height: 7)
            Text("\(vm.sightings.count) sighting\(vm.sightings.count == 1 ? "" : "s") in view")
                .font(Theme.sansMedium(13))
        }
        .foregroundStyle(c.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(c.paper, in: Capsule())
        .overlay(Capsule().strokeBorder(c.rule, lineWidth: 1.5))
        .padding(.bottom, 14)
    }

    private var loadingBadge: some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(spacing: 8) {
            ProgressView().scaleEffect(0.8).tint(c.clay)
            Text("Loading sightings…")
                .font(Theme.sansMedium(13))
        }
        .foregroundStyle(c.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(c.paper, in: Capsule())
        .overlay(Capsule().strokeBorder(c.rule, lineWidth: 1.5))
        .padding(.bottom, 14)
    }
}

/// The teardrop pin used on the map — the same silhouette as the one in the Instagram reels'
/// "the map" illustration (docs/social/instagram/build.py's `pin()`).
private struct MapPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.34),
                    control1: CGPoint(x: rect.midX - w * 0.30, y: rect.minY),
                    control2: CGPoint(x: rect.minX, y: rect.minY + h * 0.14))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                    control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.62),
                    control2: CGPoint(x: rect.midX, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.34),
                    control1: CGPoint(x: rect.midX, y: rect.maxY),
                    control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.62))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                    control1: CGPoint(x: rect.maxX, y: rect.minY + h * 0.14),
                    control2: CGPoint(x: rect.midX + w * 0.30, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

@MainActor
final class SightingMapViewModel: ObservableObject {
    @Published var sightings: [Sighting] = []
    /// The most recent sightings regardless of viewport — what search runs over,
    /// since `sightings` is narrowed to whatever the map is currently showing.
    @Published var allSightings: [Sighting] = []
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
            allSightings = result
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

#Preview {
    FirebasePreview { SightingMapView() }
}
