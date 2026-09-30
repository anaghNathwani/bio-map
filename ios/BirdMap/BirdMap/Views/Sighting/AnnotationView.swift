import SwiftUI

struct AnnotationView: View {
    @Environment(\.colorScheme) private var scheme
    let sightingID: String
    /// Set when this form was opened from the post-upload AI review card —
    /// "confirmed" (Right), "rejected" (Wrong), or "unsure". Nil for a normal,
    /// unprompted community annotation.
    let reviewOfAI: String?
    let onDone: () -> Void

    @State private var species: String
    @State private var behavior = ""
    @State private var agePlumage = ""
    @State private var confidence: Double
    @State private var isSubmitting = false
    @State private var error: String?

    private let behaviorOptions = ["Perching", "Foraging", "Flying", "Singing", "Nesting", "Swimming", "Other"]
    private let plumageOptions = ["Adult", "Juvenile", "Immature", "First winter", "Unknown"]

    init(sightingID: String, initialSpecies: String = "", initialConfidence: Double = 0.9,
         reviewOfAI: String? = nil, onDone: @escaping () -> Void) {
        self.sightingID = sightingID
        self.reviewOfAI = reviewOfAI
        self.onDone = onDone
        _species = State(initialValue: initialSpecies)
        _confidence = State(initialValue: initialConfidence)
    }

    /// "Unsure" reviews are a valid, complete annotation on their own — no species required.
    private var canSubmit: Bool {
        isSubmitting == false && (reviewOfAI == "unsure" || !species.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var confidenceColor: Color {
        switch confidence {
        case 0.8...: return .green
        case 0.5...: return .orange
        default: return .red
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    speciesSection
                    behaviorSection
                    plumageSection
                    confidenceSection

                    if let error {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(Theme.sans(13))
                        .foregroundStyle(ThemeColors(scheme: scheme).clay)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(ThemeColors(scheme: scheme).paper)
            .navigationTitle("Annotate Sighting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .tint(ThemeColors(scheme: scheme).clay)
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private var speciesSection: some View {
        let c = ThemeColors(scheme: scheme)
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Species", required: reviewOfAI != "unsure")

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(c.inkSoft)
                TextField(reviewOfAI == "unsure" ? "Leave blank if you're not sure" : "e.g. American Robin", text: $species)
                    .font(Theme.sans(15))
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(c.paperDim, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if AnnotationModerator.shared.verdict(species: species, reviewOfAI: reviewOfAI).isFlagged {
                Label("That doesn't look like a bird name we know, so it will show as flagged. Check the spelling, or leave it blank and mark it unsure.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.sans(12))
                    .foregroundStyle(c.clay)
            }
        }
        .padding(.horizontal)
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Behavior", required: false)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chipButton("Any", selected: behavior.isEmpty) { behavior = "" }
                    ForEach(behaviorOptions, id: \.self) { option in
                        chipButton(option, selected: behavior == option) { behavior = option }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var plumageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Age / Plumage", required: false)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chipButton("Unknown", selected: agePlumage.isEmpty) { agePlumage = "" }
                    ForEach(plumageOptions, id: \.self) { option in
                        chipButton(option, selected: agePlumage == option) { agePlumage = option }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var confidenceSection: some View {
        let c = ThemeColors(scheme: scheme)
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Your confidence", required: false)

            VStack(spacing: 12) {
                HStack {
                    Text("How sure are you?")
                        .font(Theme.sans(14))
                        .foregroundStyle(c.inkSoft)
                    Spacer()
                    Text("\(Int(confidence * 100))%")
                        .font(Theme.display(22, medium: true))
                        .foregroundStyle(confidenceColor)
                        .animation(.easeInOut(duration: 0.15), value: confidence)
                        .contentTransition(.numericText())
                }

                Slider(value: $confidence, in: 0.1...1.0, step: 0.05)
                    .tint(confidenceColor)
                    .animation(.easeInOut(duration: 0.15), value: confidence)

                HStack {
                    Text("Unsure").font(Theme.sans(11)).foregroundStyle(c.inkSoft)
                    Spacer()
                    Text("Certain").font(Theme.sans(11)).foregroundStyle(c.inkSoft)
                }
            }
            .padding(14)
            .background(c.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
            .padding(.horizontal)
        }
    }

    private func sectionHeader(_ title: String, required: Bool) -> some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(spacing: 8) {
            Eyebrow(text: title)
            if required {
                Text("required")
                    .font(Theme.sansSemibold(10))
                    .foregroundStyle(c.paper)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(c.clay, in: Capsule())
            }
        }
        .padding(.horizontal)
    }

    private func chipButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let c = ThemeColors(scheme: scheme)
        return Button(action: action) {
            Text(label)
                .font(Theme.sansMedium(14))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? c.ink : c.paperDim, in: Capsule())
                .foregroundStyle(selected ? c.paper : c.ink)
                .animation(.easeInOut(duration: 0.15), value: selected)
        }
    }

    private func submit() async {
        isSubmitting = true
        do {
            try await FirebaseService.shared.submitAnnotation(
                sightingID: sightingID,
                species: species.trimmingCharacters(in: .whitespaces),
                confidence: confidence,
                behavior: behavior.isEmpty ? nil : behavior,
                agePlumage: agePlumage.isEmpty ? nil : agePlumage,
                reviewOfAI: reviewOfAI
            )
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}

#Preview {
    FirebasePreview {
        AnnotationView(sightingID: "preview", initialSpecies: "American Robin", onDone: {})
    }
}
