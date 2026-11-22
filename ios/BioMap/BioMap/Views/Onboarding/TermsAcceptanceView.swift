import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Records which version of the Terms each account accepted. The local copy gates the app; the Firestore copy is the
/// record (version and server time) in case it is ever needed.
enum TermsAcceptance {
    private static func key(_ uid: String) -> String { "termsAccepted.\(uid)" }

    static func needsAcceptance(uid: String) -> Bool {
        UserDefaults.standard.string(forKey: key(uid)) != TermsText.version
    }

    static func accept(uid: String) {
        UserDefaults.standard.set(TermsText.version, forKey: key(uid))
        // Best effort: the gate is already open, and this is retried the next time the terms change.
        Task {
            try? await Firestore.firestore().collection("users").document(uid).setData([
                "termsAcceptedVersion": TermsText.version,
                "termsAcceptedAt": FieldValue.serverTimestamp(),
            ], merge: true)
        }
    }
}

/// First onboarding step, and the re-acceptance screen when the Terms change: the full text, two explicit confirmations
/// (age, and agreement to the Terms and Privacy Policy) and an agree button that stays off until both are ticked.
struct TermsAcceptanceView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var scheme
    let uid: String
    let onAccepted: () -> Void

    @State private var isOldEnough = false
    @State private var agrees = false

    private let siteURL = "https://getbiomap.web.app"

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Before you start")
                        .font(Theme.display(28, medium: true)).foregroundStyle(c.fg)
                    Text("Terms of Service · Updated \(TermsText.updated)")
                        .font(Theme.sans(13)).foregroundStyle(c.fgSoft)
                    Text(TermsText.intro).font(Theme.sans(15)).foregroundStyle(c.fg)

                    ForEach(TermsText.sections) { section in
                        Text(section.title)
                            .font(Theme.sansSemibold(16)).foregroundStyle(c.fg)
                            .padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                            switch block {
                            case .paragraph(let text):
                                Text(text).font(Theme.sans(14)).foregroundStyle(c.fg.opacity(0.9))
                            case .bullets(let items):
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(items, id: \.self) { item in
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("•")
                                            Text(item)
                                        }
                                        .font(Theme.sans(14)).foregroundStyle(c.fg.opacity(0.9))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            VStack(spacing: 12) {
                confirmation("I am at least 13 years old, or my parent or guardian agrees to these Terms for me.", isOn: $isOldEnough, c: c)
                confirmation("I have read and agree to the Terms of Service and the Privacy Policy.", isOn: $agrees, c: c)
                if let privacy = URL(string: siteURL + "/privacy") {
                    Link("Read the Privacy Policy", destination: privacy)
                        .font(Theme.sansMedium(13)).foregroundStyle(c.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    TermsAcceptance.accept(uid: uid)
                    onAccepted()
                } label: {
                    Text("Agree and continue")
                        .font(Theme.sansSemibold(16))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(c.bg)
                        .background((isOldEnough && agrees) ? c.accent : c.fgSoft.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!(isOldEnough && agrees))
                Button("Decline and sign out") { env.logout() }
                    .font(Theme.sansMedium(14)).foregroundStyle(c.fgSoft)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
            .background(c.bg.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2)))
        }
        .background(c.bg.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func confirmation(_ text: String, isOn: Binding<Bool>, c: ThemeColors) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22)).foregroundStyle(isOn.wrappedValue ? c.accent : c.fgSoft)
                Text(text).font(Theme.sans(14)).foregroundStyle(c.fg).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? [.isButton, .isSelected] : .isButton)
    }
}
