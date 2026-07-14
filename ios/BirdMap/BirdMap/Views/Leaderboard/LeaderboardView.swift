import SwiftUI

struct LeaderboardView: View {
    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading leaderboard…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        "No Entries Yet",
                        systemImage: "trophy",
                        description: Text("Start annotating sightings to appear here!")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            topThreePodium
                                .padding(.horizontal)
                                .padding(.top, 16)
                                .padding(.bottom, 24)

                            if entries.count > 3 {
                                VStack(spacing: 1) {
                                    ForEach(Array(entries.dropFirst(3).enumerated()), id: \.element.id) { index, entry in
                                        rankRow(entry: entry, rank: index + 4)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Top Observers")
            .task { await loadLeaderboard() }
            .refreshable { await loadLeaderboard() }
        }
    }

    @ViewBuilder
    private var topThreePodium: some View {
        let top = Array(entries.prefix(3))
        let base = ScreenSize.current.scale(150, compact: 120, large: 165)
        HStack(alignment: .bottom, spacing: 12) {
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
        VStack(spacing: 8) {
            Text(medalEmoji(for: rank - 1))
                .font(.system(size: ScreenSize.current.scale(rank == 1 ? 36 : 28, compact: rank == 1 ? 28 : 22)))

            Text(entry.username)
                .font(rank == 1 ? .headline : .subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(entry.annotationCount)")
                .font(.title3.bold())
                .foregroundStyle(podiumColor(rank: rank))

            Text("annotations")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(podiumColor(rank: rank).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(podiumColor(rank: rank).opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func rankRow(entry: LeaderboardEntry, rank: Int) -> some View {
        HStack(spacing: 14) {
            Text("#\(rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(String(entry.username.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(Color.teal)
            }

            Text(entry.username)
                .font(.body)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(entry.annotationCount)")
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func podiumColor(rank: Int) -> Color {
        switch rank {
        case 1: return Color(hue: 0.12, saturation: 0.85, brightness: 0.8) // gold
        case 2: return Color(hue: 0.6, saturation: 0.1, brightness: 0.65) // silver
        case 3: return Color(hue: 0.07, saturation: 0.65, brightness: 0.65) // bronze
        default: return .teal
        }
    }

    private func medalEmoji(for index: Int) -> String {
        switch index {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "🐦"
        }
    }

    private func loadLeaderboard() async {
        isLoading = true
        entries = (try? await APIClient.shared.leaderboard()) ?? []
        isLoading = false
    }
}
