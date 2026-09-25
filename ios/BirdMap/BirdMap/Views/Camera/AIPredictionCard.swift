import SwiftUI

/// The user's verdict on an AI prediction, shown right after a photo or audio
/// sighting uploads. Maps to `AnnotationItem.reviewOfAI` in Firestore.
enum AIVerdict {
    case confirmed, rejected, unsure

    var reviewOfAI: String {
        switch self {
        case .confirmed: return "confirmed"
        case .rejected: return "rejected"
        case .unsure: return "unsure"
        }
    }
}

/// Shows the model's predicted species, a reference photo, and Right/Wrong/Unsure
/// buttons. Used after both photo (on-device) and audio (server-side BirdNET)
/// classification. Reused by CameraView and AudioRecorderView.
struct AIPredictionCard: View {
    let species: String
    let confidence: Double
    let onVerdict: (AIVerdict) -> Void

    @State private var referenceImageURL: URL?
    @State private var isLoadingReference = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").symbolRenderingMode(.multicolor)
                Text("We think this is a…")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(Int(confidence * 100))% confident")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                referenceImage
                VStack(alignment: .leading, spacing: 4) {
                    Text(species)
                        .font(.title3.bold())
                    Text("Is this right?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                verdictButton("Right", icon: "checkmark.circle.fill", color: .green) {
                    onVerdict(.confirmed)
                }
                verdictButton("Wrong", icon: "xmark.circle.fill", color: .red) {
                    onVerdict(.rejected)
                }
                verdictButton("Unsure", icon: "questionmark.circle.fill", color: .orange) {
                    onVerdict(.unsure)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .task { await loadReferenceImage() }
    }

    @ViewBuilder
    private var referenceImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.teal.opacity(0.1))
            if let url = referenceImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholderIcon
                    }
                }
            } else if isLoadingReference {
                ProgressView()
            } else {
                placeholderIcon
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var placeholderIcon: some View {
        Image(systemName: "bird.fill")
            .foregroundStyle(Color.teal.opacity(0.4))
    }

    private func verdictButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(color)
        }
    }

    private func loadReferenceImage() async {
        defer { isLoadingReference = false }
        guard let info = try? await APIClient.shared.birdInfo(species: species),
              let urlString = info.imageURL, let url = URL(string: urlString) else { return }
        referenceImageURL = url
    }
}

#Preview {
    FirebasePreview {
        AIPredictionCard(species: "American Robin", confidence: 0.92, onVerdict: { _ in })
            .padding()
    }
}
