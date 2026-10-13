import SwiftUI

struct LoginView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.colorScheme) private var scheme
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isLoading = false
    @State private var error: String?

    private let screen = ScreenSize.current

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        ZStack {
            c.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                        .padding(.bottom, screen.scale(40, compact: 26, large: 48))

                    formCard
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        let c = ThemeColors(scheme: scheme)
        return VStack(spacing: 16) {
            let markSize = screen.scale(84, compact: 66, large: 96)
            BirdMark()
                .stroke(c.fg, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: markSize, height: markSize)
                .padding(.top, screen.scale(64, compact: 40, large: 76))

            Text("BioMap")
                .font(Theme.displayItalic(screen.scale(42, compact: 34, large: 46)))
                .foregroundStyle(c.fg)

            Text("Citizen science, one sighting at a time")
                .font(Theme.sans(15))
                .foregroundStyle(c.fgSoft)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Form card

    private var formCard: some View {
        let c = ThemeColors(scheme: scheme)
        return VStack(spacing: 16) {
            fieldsStack

            if let error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                }
                .font(Theme.sans(13))
                .foregroundStyle(c.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(c.accentSoft.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(c.accent.opacity(0.5), lineWidth: 1))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            submitButton
            toggleButton

            HStack(spacing: 10) {
                HairlineRule()
                Text("or").font(Theme.sans(12)).foregroundStyle(c.fgSoft)
                HairlineRule()
            }
            .padding(.vertical, 2)

            googleSignInButton
        }
        .padding(22)
        .background(c.bg, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
    }

    // MARK: - Fields

    private var fieldsStack: some View {
        VStack(spacing: 10) {
            paperField {
                Image(systemName: "envelope").frame(width: 20)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            if isRegistering {
                paperField {
                    Image(systemName: "person").frame(width: 20)
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            paperField {
                Image(systemName: "lock").frame(width: 20)
                SecureField("Password", text: $password)
            }
        }
        .animation(.spring(duration: 0.35), value: isRegistering)
    }

    @ViewBuilder
    private func paperField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let c = ThemeColors(scheme: scheme)
        HStack(spacing: 10) { content() }
            .font(Theme.sans(16))
            .foregroundStyle(c.fg)
            .tint(c.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Buttons

    private var submitButton: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: isRegistering ? "person.badge.plus" : "arrow.right")
                }
                Text(isLoading ? "Please wait…" : (isRegistering ? "Create account" : "Sign in"))
            }
        }
        .buttonStyle(PillButtonStyle())
        .disabled(isLoading)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }

    private var toggleButton: some View {
        let c = ThemeColors(scheme: scheme)
        return Button {
            withAnimation(.spring(duration: 0.35)) {
                isRegistering.toggle()
                error = nil
            }
        } label: {
            (Text(isRegistering ? "Already have an account? " : "New here? ")
                + Text(isRegistering ? "Sign in" : "Create account").foregroundStyle(c.accent))
                .font(Theme.sans(14))
                .foregroundStyle(c.fgSoft)
        }
        .padding(.top, 2)
    }

    private var googleSignInButton: some View {
        Button {
            Task { await signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                Text("G").font(Theme.sansSemibold(16))
                Text("Sign in with Google").font(Theme.sansMedium(16))
            }
        }
        .buttonStyle(PillButtonStyle(prominent: false))
        .disabled(isLoading)
    }

    // MARK: - Auth logic

    private func submit() async {
        withAnimation(.easeInOut(duration: 0.2)) { isLoading = true; error = nil }
        let trimEmail = email.trimmingCharacters(in: .whitespaces)
        let trimUser = username.trimmingCharacters(in: .whitespaces)
        do {
            if isRegistering {
                guard trimUser.count >= 2 else {
                    withAnimation { error = "Username must be at least 2 characters" }
                    isLoading = false; return
                }
                try await FirebaseService.shared.register(email: trimEmail, username: trimUser, password: password)
                env.saveUsername(trimUser)
            } else {
                try await FirebaseService.shared.login(email: trimEmail, password: password)
                if let name = await FirebaseService.shared.fetchUsername() { env.saveUsername(name) }
            }
        } catch {
            withAnimation(.easeInOut(duration: 0.2)) { self.error = error.localizedDescription }
        }
        withAnimation(.easeInOut(duration: 0.2)) { isLoading = false }
    }

    private func signInWithGoogle() async {
        isLoading = true
        do {
            try await FirebaseService.shared.signInWithGoogle()
            if let name = await FirebaseService.shared.fetchUsername() { env.saveUsername(name) }
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

#Preview {
    FirebasePreview { LoginView().environmentObject(AppEnvironment()) }
}
