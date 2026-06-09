import SwiftUI

struct LeaderboardView: View {
    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading...")
                } else {
                    List {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 16) {
                                Text(medal(for: index))
                                    .font(.title2)
                                    .frame(width: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.username).font(.headline)
                                    Text("\(entry.annotationCount) annotations")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text("#\(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Top Observers")
            .task { await loadLeaderboard() }
            .refreshable { await loadLeaderboard() }
        }
    }

    private func loadLeaderboard() async {
        isLoading = true
        entries = (try? await APIClient.shared.leaderboard()) ?? []
        isLoading = false
    }

    private func medal(for index: Int) -> String {
        switch index {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "🐦"
        }
    }
}
