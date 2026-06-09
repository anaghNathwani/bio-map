import SwiftUI

struct AnnotationView: View {
    let sightingID: UUID
    let onDone: () -> Void

    @State private var species = ""
    @State private var behavior = ""
    @State private var agePlumage = ""
    @State private var confidence: Double = 0.9
    @State private var isSubmitting = false
    @State private var error: String?

    private let behaviorOptions = ["Perching", "Foraging", "Flying", "Singing", "Nesting", "Swimming", "Other"]
    private let plumageOptions = ["Adult", "Juvenile", "Immature", "First winter", "Unknown"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Species") {
                    TextField("e.g. American Robin", text: $species)
                        .autocorrectionDisabled()
                }

                Section("Behavior") {
                    Picker("Behavior", selection: $behavior) {
                        Text("Not specified").tag("")
                        ForEach(behaviorOptions, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Age / Plumage") {
                    Picker("Age / Plumage", selection: $agePlumage) {
                        Text("Unknown").tag("")
                        ForEach(plumageOptions, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Your confidence") {
                    VStack(alignment: .leading) {
                        Text("\(Int(confidence * 100))%")
                        Slider(value: $confidence, in: 0.1...1.0, step: 0.05)
                    }
                }

                if let error {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("Annotate Sighting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving..." : "Save") {
                        Task { await submit() }
                    }
                    .disabled(species.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        do {
            try await APIClient.shared.submitAnnotation(
                sightingID: sightingID,
                species: species.trimmingCharacters(in: .whitespaces),
                confidence: confidence,
                behavior: behavior.isEmpty ? nil : behavior,
                agePlumage: agePlumage.isEmpty ? nil : agePlumage
            )
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}
