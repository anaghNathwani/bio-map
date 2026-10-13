import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A candidate bird detected alongside the primary one — either a second/third
/// distinct species BirdNET heard in one recording, or (once photo object
/// detection ships) a separate bird instance cropped from one photo.
/// `croppedImage` is nil for audio; populated for photo crops.
struct BirdCandidate: Identifiable {
    let id = UUID()
    let species: String
    let confidence: Double
    var croppedImage: UIImage? = nil
}

/// Shown below the primary AIPredictionCard when more than one distinct bird
/// was detected — "We also heard/saw…". Each row submits its own annotation
/// directly (no full form) to keep reviewing several birds fast: Right posts
/// immediately, Wrong expands an inline text field, Unsure posts immediately
/// with no species. Used by both AudioRecorderView (today) and CameraView
/// (once photo multi-bird detection is wired in).
struct AdditionalBirdsSection: View {
    @Environment(\.colorScheme) private var scheme
    let sightingID: String
    let candidates: [BirdCandidate]

    @State private var resolved: Set<UUID> = []
    @State private var correctingID: UUID?
    @State private var correctionText = ""
    @State private var submitError: String?

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Also detected")

                ForEach(candidates) { candidate in
                    row(for: candidate)
                }

                if let submitError {
                    Text(submitError)
                        .font(Theme.sans(11))
                        .foregroundStyle(c.accent)
                }
            }
            .padding(14)
            .background(c.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func row(for candidate: BirdCandidate) -> some View {
        let c = ThemeColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let img = candidate.croppedImage {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.species).font(Theme.sansMedium(14)).foregroundStyle(c.fg)
                    Text("\(Int(candidate.confidence * 100))% confident")
                        .font(Theme.sans(11)).foregroundStyle(c.fgSoft)
                }
                Spacer()

                if resolved.contains(candidate.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 6) {
                        smallButton("checkmark", .green) {
                            Task { await submit(candidate, species: candidate.species, verdict: .confirmed) }
                        }
                        smallButton("xmark", .red) {
                            correctingID = candidate.id
                            correctionText = ""
                        }
                        smallButton("questionmark", c.fgSoft) {
                            Task { await submit(candidate, species: "", verdict: .unsure) }
                        }
                    }
                }
            }

            if correctingID == candidate.id {
                HStack(spacing: 8) {
                    TextField("What is it actually?", text: $correctionText)
                        .font(Theme.sans(14))
                        .autocorrectionDisabled()
                        .padding(8)
                        .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button("Save") {
                        Task { await submit(candidate, species: correctionText.trimmingCharacters(in: .whitespaces), verdict: .rejected) }
                    }
                    .font(Theme.sansSemibold(13))
                    .foregroundStyle(c.accent)
                    .disabled(correctionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func smallButton(_ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .padding(6)
                .background(color.opacity(0.12), in: Circle())
        }
    }

    private func submit(_ candidate: BirdCandidate, species: String, verdict: AIVerdict) async {
        do {
            try await FirebaseService.shared.submitAnnotation(
                sightingID: sightingID,
                species: species,
                confidence: verdict == .confirmed ? 0.9 : (verdict == .rejected ? 0.6 : 0.5),
                behavior: nil,
                agePlumage: nil,
                reviewOfAI: verdict.reviewOfAI
            )
            resolved.insert(candidate.id)
            correctingID = nil
        } catch {
            submitError = error.localizedDescription
        }
    }
}

#Preview {
    FirebasePreview {
        AdditionalBirdsSection(
            sightingID: "preview",
            candidates: [BirdCandidate(species: "House Finch", confidence: 0.71),
                         BirdCandidate(species: "Song Sparrow", confidence: 0.55)]
        )
        .padding()
    }
}
