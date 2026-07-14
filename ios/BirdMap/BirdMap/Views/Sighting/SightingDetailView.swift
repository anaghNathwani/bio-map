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
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let detail {
                    detailContent(detail)
                }
            }
            .navigationTitle("Sighting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAnnotate = true
                    } label: {
                        Label("Annotate", systemImage: "pencil.and.list.clipboard")
                    }
                    .disabled(detail == nil)
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

    @ViewBuilder
    private func detailContent(_ detail: SightingDetail) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                photoHeader(detail)

                VStack(alignment: .leading, spacing: 20) {
                    metadataSection(detail)
                    annotationsSection(detail)
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func photoHeader(_ detail: SightingDetail) -> some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: URL(string: detail.photoURL)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    Rectangle().fill(Color(.secondarySystemBackground))
                        .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary))
                default:
                    Rectangle().fill(Color(.secondarySystemBackground))
                        .overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity)
            .proportionalHeight(0.36, min: 200, max: 380)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .center,
                endPoint: .bottom
            )

            if let species = detail.aiSpeciesSuggestion {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Suggestion")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(species)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if let conf = detail.aiConfidence {
                        Text("\(Int(conf * 100))%")
                            .font(.title3.bold())
                            .foregroundStyle(confidenceColor(conf))
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func metadataSection(_ detail: SightingDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notes = detail.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.teal)
                Text(String(format: "%.4f, %.4f", detail.latitude, detail.longitude))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func annotationsSection(_ detail: SightingDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Community Annotations")
                    .font(.headline)
                Spacer()
                Text("\(detail.annotations.count)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.teal, in: Capsule())
            }

            if detail.annotations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No annotations yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Be the first to identify this bird!")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                VStack(spacing: 8) {
                    ForEach(detail.annotations) { ann in
                        annotationCard(ann)
                    }
                }
            }

            Button {
                showAnnotate = true
            } label: {
                Label("Add Your Annotation", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.teal)
                    .fontWeight(.medium)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func annotationCard(_ ann: AnnotationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(String(ann.username.prefix(1)).uppercased())
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.teal)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(ann.species)
                        .font(.subheadline.bold())
                    Spacer()
                    confidenceBadge(ann.confidence)
                }
                if let behavior = ann.behavior {
                    Label(behavior, systemImage: "figure.walk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("by \(ann.username)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption.bold())
            .foregroundStyle(confidenceColor(confidence))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(confidenceColor(confidence).opacity(0.15), in: Capsule())
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...: return .green
        case 0.5...: return .orange
        default: return .red
        }
    }

    private func loadDetail() async {
        isLoading = true
        detail = try? await APIClient.shared.sightingDetail(id: sightingID)
        isLoading = false
    }
}
