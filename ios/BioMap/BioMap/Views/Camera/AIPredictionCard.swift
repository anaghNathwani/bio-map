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
    @Environment(\.colorScheme) private var scheme
    let species: String
    let confidence: Double
    let onVerdict: (AIVerdict) -> Void

    @State private var referenceImageURL: URL?
    @State private var isLoadingReference = true

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Eyebrow(text: "Suggestion")
                Spacer()
                Text("\(Int(confidence * 100))% confident")
                    .font(Theme.sansMedium(12))
                    .foregroundStyle(c.inkSoft)
            }

            HStack(spacing: 12) {
                referenceImage
                VStack(alignment: .leading, spacing: 4) {
                    Text(species)
                        .font(Theme.display(19, medium: true))
                        .foregroundStyle(c.ink)
                    Text("Is this right?")
                        .font(Theme.sans(13))
                        .foregroundStyle(c.inkSoft)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                verdictButton("Right", icon: "checkmark", color: .green) {
                    onVerdict(.confirmed)
                }
                verdictButton("Wrong", icon: "xmark", color: .red) {
                    onVerdict(.rejected)
                }
                verdictButton("Unsure", icon: "questionmark", color: c.inkSoft) {
                    onVerdict(.unsure)
                }
            }
        }
        .padding(16)
        .background(c.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
        .padding(.horizontal)
        .task { await loadReferenceImage() }
    }

    @ViewBuilder
    private var referenceImage: some View {
        let c = ThemeColors(scheme: scheme)
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.paperDim)
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
                ProgressView().tint(c.clay)
            } else {
                placeholderIcon
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var placeholderIcon: some View {
        BirdMark()
            .stroke(ThemeColors(scheme: scheme).inkSoft, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .padding(16)
    }

    private func verdictButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        let c = ThemeColors(scheme: scheme)
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(label).font(Theme.sansSemibold(12))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(c.paperDim, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.4), lineWidth: 1.4))
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
