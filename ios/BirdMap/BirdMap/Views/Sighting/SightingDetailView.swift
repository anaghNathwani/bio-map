import SwiftUI

struct SightingDetailView: View {
    let sightingID: UUID
    @State private var detail: SightingDetail?
    @State private var isLoading = true
    @State private var showAnnotate = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading...")
                } else if let detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            AsyncImage(url: URL(string: detail.photoURL)) { img in
                                img.resizable().scaledToFit()
                            } placeholder: {
                                Rectangle().fill(.secondary.opacity(0.2))
                                    .aspectRatio(4/3, contentMode: .fit)
                                    .overlay(ProgressView())
                            }
                            .cornerRadius(12)

                            VStack(alignment: .leading, spacing: 8) {
                                if let species = detail.aiSpeciesSuggestion {
                                    HStack {
                                        Image(systemName: "sparkles")
                                        Text("AI: **\(species)**")
                                        if let conf = detail.aiConfidence {
                                            Text("(\(Int(conf * 100))%)")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.teal)
                                }

                                if let notes = detail.notes {
                                    Text(notes).font(.body)
                                }

                                Text("📍 \(detail.latitude, specifier: "%.4f"), \(detail.longitude, specifier: "%.4f")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)

                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Community Annotations")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(detail.annotations.count)")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)

                                ForEach(detail.annotations) { ann in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ann.species).bold()
                                            if let behavior = ann.behavior {
                                                Text(behavior).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(ann.username)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text("\(Int(ann.confidence * 100))% sure")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                    Divider().padding(.leading)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sighting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Annotate") { showAnnotate = true }
                }
            }
            .sheet(isPresented: $showAnnotate) {
                if let detail {
                    AnnotationView(sightingID: detail.id) {
                        showAnnotate = false
                        Task { await loadDetail() }
                    }
                }
            }
            .task { await loadDetail() }
        }
    }

    private func loadDetail() async {
        isLoading = true
        detail = try? await APIClient.shared.sightingDetail(id: sightingID)
        isLoading = false
    }
}
