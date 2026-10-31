import WidgetKit
import SwiftUI

struct SightingsEntry: TimelineEntry {
    let date: Date
    let total: Int?
    let latest: Date?
}

/// Reads the public `sightings` collection straight from Firestore's REST API (the security rules allow
/// public reads, the same as the website's map), so the widget needs no sign-in or shared storage.
enum SightingsAPI {
    private static let documents = "https://firestore.googleapis.com/v1/projects/birdmap-citizenscience/databases/(default)/documents"

    private static var apiKey: String? {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let plist = NSDictionary(contentsOf: url) else { return nil }
        return plist["API_KEY"] as? String
    }

    private static func post(_ method: String, _ body: [String: Any]) async -> [[String: Any]]? {
        guard let key = apiKey, let url = URL(string: "\(documents):\(method)?key=\(key)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    static func total() async -> Int? {
        let body: [String: Any] = ["structuredAggregationQuery": [
            "structuredQuery": ["from": [["collectionId": "sightings"]]],
            "aggregations": [["alias": "n", "count": [String: Any]()]],
        ]]
        guard let rows = await post("runAggregationQuery", body),
              let fields = (rows.first?["result"] as? [String: Any])?["aggregateFields"] as? [String: Any],
              let n = (fields["n"] as? [String: Any])?["integerValue"] as? String else { return nil }
        return Int(n)
    }

    static func latest() async -> Date? {
        let body: [String: Any] = ["structuredQuery": [
            "from": [["collectionId": "sightings"]],
            "orderBy": [["field": ["fieldPath": "createdAt"], "direction": "DESCENDING"]],
            "limit": 1,
            "select": ["fields": [["fieldPath": "createdAt"]]],
        ]]
        guard let rows = await post("runQuery", body),
              let fields = (rows.first?["document"] as? [String: Any])?["fields"] as? [String: Any],
              let stamp = (fields["createdAt"] as? [String: Any])?["timestampValue"] as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
    }
}

struct SightingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SightingsEntry {
        SightingsEntry(date: .now, total: 128, latest: .now.addingTimeInterval(-3_600))
    }

    func getSnapshot(in context: Context, completion: @escaping (SightingsEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SightingsEntry>) -> Void) {
        Task {
            let entry = await load()
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
        }
    }

    private func load() async -> SightingsEntry {
        async let total = SightingsAPI.total()
        async let latest = SightingsAPI.latest()
        return SightingsEntry(date: .now, total: await total, latest: await latest)
    }
}

struct SightingsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: SightingsEntry

    private var accent: Color { Theme.accent(scheme) }
    private var count: String { entry.total.map(String.init) ?? "–" }
    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: small
            }
        }
        .containerBackground(for: .widget) { isAccessory ? Color.clear : Color(.systemBackground) }
    }

    @ViewBuilder private var latestLine: some View {
        if let latest = entry.latest {
            Text("Latest \(latest, format: .relative(presentation: .named))")
        } else {
            Text("Tap to report a sighting")
        }
    }

    private var mark: some View {
        BirdMark()
            .stroke(accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .frame(width: 26, height: 26)
    }

    // MARK: Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            mark
            Spacer(minLength: 6)
            Text(count)
                .font(.system(size: 38, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("sightings")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            latestLine
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(WidgetLink.photo)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                mark
                Spacer(minLength: 6)
                Text(count)
                    .font(.system(size: 38, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("sightings on BioMap")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                latestLine
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                Link(destination: WidgetLink.photo) {
                    Label("Photo", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(accent, in: Capsule())
                }
                Link(destination: WidgetLink.sound) {
                    Label("Sound", systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(accent)
                        .background(Theme.accentSoft(scheme), in: Capsule())
                }
            }
            .frame(width: 130)
        }
    }

    // MARK: Lock screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            BirdMark()
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .padding(13)
        }
        .widgetAccentable()
        .widgetURL(WidgetLink.photo)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            BirdMark()
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 22, height: 22)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text("BioMap").font(.headline)
                Text("\(count) sightings").font(.caption)
                latestLine.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .widgetURL(WidgetLink.photo)
    }

    private var inline: some View {
        Text("BioMap · \(count) sightings")
            .widgetURL(WidgetLink.photo)
    }
}

struct SightingsWidget: Widget {
    let kind = "com.biomap.widget.sightings"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SightingsProvider()) { entry in
            SightingsWidgetView(entry: entry)
        }
        .configurationDisplayName("BioMap")
        .description("Community sightings at a glance, and a quick way to report one.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
