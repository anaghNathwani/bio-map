import SwiftUI

struct AnnotationView: View {
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
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
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
                            Text("Save").bold()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private var speciesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Species", icon: "bird.fill", required: reviewOfAI != "unsure")

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(reviewOfAI == "unsure" ? "Leave blank if you're not sure" : "e.g. American Robin", text: $species)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Behavior", icon: "figure.walk", required: false)

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
            sectionHeader("Age / Plumage", icon: "feather", required: false)

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
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Your Confidence", icon: "percent", required: false)

            VStack(spacing: 12) {
                HStack {
                    Text("How sure are you?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(confidence * 100))%")
                        .font(.title2.bold())
                        .foregroundStyle(confidenceColor)
                        .animation(.easeInOut(duration: 0.15), value: confidence)
                        .contentTransition(.numericText())
                }

                Slider(value: $confidence, in: 0.1...1.0, step: 0.05)
                    .tint(confidenceColor)
                    .animation(.easeInOut(duration: 0.15), value: confidence)

                HStack {
                    Text("Unsure")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Certain")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private func sectionHeader(_ title: String, icon: String, required: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Color.teal)
                .font(.subheadline)
            Text(title)
                .font(.subheadline.bold())
            if required {
                Text("required")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.teal, in: Capsule())
            }
        }
        .padding(.horizontal)
    }

    private func chipButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    selected ? Color.teal : Color(.secondarySystemGroupedBackground),
                    in: Capsule()
                )
                .foregroundStyle(selected ? .white : .primary)
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
