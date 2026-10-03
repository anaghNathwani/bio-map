import SwiftUI

struct LeaderboardView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = true

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading leaderboard…")
                        .tint(c.clay)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    VStack(spacing: 10) {
                        BirdMark()
                            .stroke(c.inkSoft, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 56, height: 56)
                        Text("No entries yet").font(Theme.display(20, medium: true)).foregroundStyle(c.ink)
                        Text("Start annotating sightings to appear here.")
                            .font(Theme.sans(14)).foregroundStyle(c.inkSoft)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            topThreePodium
                                .padding(.horizontal)
                                .padding(.top, 16)
                                .padding(.bottom, 24)

                            if entries.count > 3 {
                                VStack(spacing: 0) {
                                    ForEach(Array(entries.dropFirst(3).enumerated()), id: \.element.id) { index, entry in
                                        if index > 0 { HairlineRule() }
                                        rankRow(entry: entry, rank: index + 4)
                                    }
                                }
                                .background(c.paper)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .background(c.paper)
                }
            }
            .background(c.paper)
            .navigationTitle("Top Observers")
            .task { await loadLeaderboard() }
            .refreshable { await loadLeaderboard() }
        }
    }

    @ViewBuilder
    private var topThreePodium: some View {
        let top = Array(entries.prefix(3))
        let base = ScreenSize.current.scale(150, compact: 120, large: 165)
        HStack(alignment: .bottom, spacing: 10) {
            if top.count > 1 {
                podiumCard(entry: top[1], rank: 2, height: base * 0.8)
            }
            if top.count > 0 {
                podiumCard(entry: top[0], rank: 1, height: base)
            }
            if top.count > 2 {
                podiumCard(entry: top[2], rank: 3, height: base * 0.67)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func podiumCard(entry: LeaderboardEntry, rank: Int, height: CGFloat) -> some View {
        let c = ThemeColors(scheme: scheme)
        return VStack(spacing: 8) {
            Text(rank == 1 ? "1st" : rank == 2 ? "2nd" : "3rd")
                .font(Theme.displayItalic(rank == 1 ? 28 : 22))
                .foregroundStyle(c.clay)

            Text(entry.username)
                .font(Theme.sansSemibold(rank == 1 ? 15 : 14))
                .foregroundStyle(c.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(entry.annotationCount)")
                .font(Theme.display(20, medium: true))
                .foregroundStyle(c.ink)

            Text("annotations")
                .font(Theme.sans(11))
                .foregroundStyle(c.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(height: height)
        .background(c.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(rank == 1 ? c.clay.opacity(0.7) : c.rule, lineWidth: rank == 1 ? 1.8 : 1.5))
    }

    private func rankRow(entry: LeaderboardEntry, rank: Int) -> some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(spacing: 14) {
            Text("\(rank)")
                .font(Theme.displayItalic(16))
                .foregroundStyle(c.inkSoft)
                .frame(width: 28, alignment: .trailing)

            ZStack {
                Circle().strokeBorder(c.rule, lineWidth: 1.5).frame(width: 36, height: 36)
                Text(String(entry.username.prefix(1)).uppercased())
                    .font(Theme.sansSemibold(15))
                    .foregroundStyle(c.clay)
            }

            Text(entry.username)
                .font(Theme.sans(15))
                .foregroundStyle(c.ink)

            Spacer()

            Text("\(entry.annotationCount)")
                .font(Theme.sansSemibold(14))
                .foregroundStyle(c.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }


    private func loadLeaderboard() async {
        isLoading = true
        entries = (try? await FirebaseService.shared.fetchLeaderboard()) ?? []
        isLoading = false
    }
}

#Preview {
    FirebasePreview { LeaderboardView() }
}
