import SwiftUI
import CoreLocation

/// Every sighting reported at one place, shown on the map as a single pin.
struct SightingGroup: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    /// Newest first.
    let sightings: [Sighting]

    /// Sightings within ~11 m (4 decimal places) of each other count as the same
    /// place — GPS fixes for two people standing at one spot are never
    /// bit-identical, so an exact match would almost never group anything.
    static func grouping(_ sightings: [Sighting]) -> [SightingGroup] {
        var buckets: [String: [Sighting]] = [:]
        for sighting in sightings {
            let key = "\(Int((sighting.latitude * 10_000).rounded())),\(Int((sighting.longitude * 10_000).rounded()))"
            buckets[key, default: []].append(sighting)
        }
        return buckets.map { key, members in
            let sorted = members.sorted {
                ($0.createdAt?.dateValue() ?? .distantPast) > ($1.createdAt?.dateValue() ?? .distantPast)
            }
            let latitude = sorted.map(\.latitude).reduce(0, +) / Double(sorted.count)
            let longitude = sorted.map(\.longitude).reduce(0, +) / Double(sorted.count)
            return SightingGroup(
                id: key,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                sightings: sorted
            )
        }
    }
}

/// Sightings the user has bookmarked. Kept on this device only (UserDefaults) —
/// there's no account-level "saved" data in Firestore, and Firestore rules only
/// let a user write their own profile doc anyway.
@MainActor
final class SavedSightings: ObservableObject {
    static let shared = SavedSightings()
    private static let key = "saved_sighting_ids"

    @Published private(set) var ids: Set<String>

    private init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isSaved(_ id: String?) -> Bool {
        guard let id else { return false }
        return ids.contains(id)
    }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UserDefaults.standard.set(Array(ids), forKey: Self.key)
    }
}

/// The list shown when a pin holds more than one sighting: pick one to read
/// about it, annotate it, or save it.
struct SightingListView: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var emptyMessage = "Nothing here yet."
    let sightings: [Sighting]

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        NavigationStack {
            Group {
                if sightings.isEmpty {
                    VStack(spacing: 10) {
                        BirdMark()
                            .stroke(c.fgSoft, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 48, height: 48)
                        Text(emptyMessage)
                            .font(Theme.sans(14))
                            .foregroundStyle(c.fgSoft)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(c.bg)
                } else {
                    List(sightings) { sighting in
                        NavigationLink {
                            SightingDetailView(sightingID: sighting.id ?? "", embedded: true)
                        } label: {
                            SightingRow(sighting: sighting)
                        }
                        .listRowBackground(c.bg)
                    }
                    .scrollContentBackground(.hidden)
                    .background(c.bg)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SightingRow: View {
    @Environment(\.colorScheme) private var scheme
    let sighting: Sighting
    @ObservedObject private var saved = SavedSightings.shared
    @State private var thumbnail: UIImage?

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        HStack(spacing: 12) {
            thumbnailView
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(sighting.displaySpecies ?? "Unidentified")
                    .font(Theme.sansSemibold(15))
                    .foregroundStyle(c.fg)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(sighting.isAudio ? "Recording" : "Photo",
                          systemImage: sighting.isAudio ? "waveform" : "camera.fill")
                    if let date = sighting.createdAt?.dateValue() {
                        Text("·")
                        Text(date, format: .relative(presentation: .named))
                    }
                }
                .font(Theme.sans(12))
                .foregroundStyle(c.fgSoft)
                if let username = sighting.username {
                    Text("by \(username)")
                        .font(Theme.sans(11))
                        .foregroundStyle(c.fgSoft.opacity(0.75))
                }
            }

            Spacer(minLength: 0)

            if sighting.annotationCount > 0 {
                Text("\(sighting.annotationCount)")
                    .font(Theme.sansSemibold(11))
                    .foregroundStyle(c.bg)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(c.accent, in: Capsule())
            }
            if saved.isSaved(sighting.id) {
                Image(systemName: "bookmark.fill").foregroundStyle(c.accent)
            }
        }
        .padding(.vertical, 2)
        .task(id: sighting.id) {
            guard !sighting.isAudio, let uri = sighting.photoURL else { return }
            // Photos are embedded as base64 (up to ~700 KB) — decode and shrink
            // off the main thread rather than in every row render.
            thumbnail = await Task.detached(priority: .userInitiated) {
                DataURI.decode(uri)
                    .flatMap(UIImage.init(data:))?
                    .preparingThumbnail(of: CGSize(width: 160, height: 160))
            }.value
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        let c = ThemeColors(scheme: scheme)
        if sighting.isAudio {
            ZStack {
                c.fg
                Image(systemName: "waveform").foregroundStyle(c.bg)
            }
        } else if let thumbnail {
            Image(uiImage: thumbnail).resizable().scaledToFill()
        } else {
            ZStack {
                c.bgRaised
                Image(systemName: "photo").foregroundStyle(c.fgSoft)
            }
        }
    }
}

/// Everything the user has bookmarked, fetched by id so it isn't limited to
/// whatever happens to be inside the current map viewport.
struct SavedSightingsView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var saved = SavedSightings.shared
    @State private var loaded: [Sighting] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                BioLoader(size: 110)
            } else {
                SightingListView(
                    title: "Saved",
                    emptyMessage: "No saved sightings yet — tap the bookmark on any sighting to keep it here.",
                    sightings: loaded.filter { saved.isSaved($0.id) }
                )
            }
        }
        .task {
            loaded = await FirebaseService.shared.fetchSightings(ids: Array(saved.ids))
            isLoading = false
        }
    }
}

#Preview("SightingListView") {
    FirebasePreview {
        SightingListView(title: "2 sightings here", sightings: [PreviewSupport.sighting, PreviewSupport.sighting])
    }
}

#Preview("SightingRow") {
    FirebasePreview { SightingRow(sighting: PreviewSupport.sighting) }
}

#Preview("SavedSightingsView") {
    FirebasePreview { SavedSightingsView() }
}
