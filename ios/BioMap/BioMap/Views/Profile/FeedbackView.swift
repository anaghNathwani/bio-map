import SwiftUI

/// "Report a bug or suggest a feature" — writes to Firestore's `feedback` collection through
/// FirebaseService.submitFeedback.
struct FeedbackView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var kind: FirebaseService.FeedbackKind = .bug
    @State private var message = ""
    @State private var isSending = false
    @State private var sent = false
    @State private var errorText: String?

    private let maxLength = 4000

    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        NavigationStack {
            Group {
                if sent {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(c.accent)
                        Text("Thank you")
                            .font(Theme.display(26, medium: true))
                            .foregroundStyle(c.fg)
                        Text("Your note reached the team.")
                            .font(Theme.sans(14))
                            .foregroundStyle(c.fgSoft)
                        Button("Done") { dismiss() }
                            .buttonStyle(PillButtonStyle())
                            .padding(.top, 8)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form(c)
                }
            }
            .background(c.bg)
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .tint(c.accent)
            .toolbar {
                if !sent {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { Task { await send() } }
                            .disabled(trimmed.isEmpty || isSending)
                            .overlay { if isSending { ProgressView().scaleEffect(0.8) } }
                    }
                }
            }
        }
    }

    private func form(_ c: ThemeColors) -> some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(FirebaseService.FeedbackKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(c.bg)
            }

            Section {
                TextEditor(text: $message)
                    .font(Theme.sans(15))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .onChange(of: message) { _, new in
                        if new.count > maxLength { message = String(new.prefix(maxLength)) }
                    }
                    .listRowBackground(c.bg)
            } header: {
                Text(kind == .bug ? "What went wrong?" : kind == .feature ? "What would you like to see?" : "Your message")
            } footer: {
                Text(kind == .bug
                     ? "What you did, what you expected, and what happened instead. Your app version and device model are attached automatically."
                     : "Your app version and device model are attached automatically.")
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(Theme.sans(12))
                        .foregroundStyle(c.accent)
                        .listRowBackground(c.bg)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func send() async {
        isSending = true
        errorText = nil
        do {
            try await FirebaseService.shared.submitFeedback(
                kind: kind, message: trimmed, username: env.username, email: env.user?.email)
            sent = true
        } catch {
            errorText = "Couldn't send that right now. Check your connection and try again."
        }
        isSending = false
    }
}

#Preview {
    FirebasePreview { FeedbackView().environmentObject(AppEnvironment()) }
}
