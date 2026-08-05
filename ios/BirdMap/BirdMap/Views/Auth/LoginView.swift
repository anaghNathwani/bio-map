import SwiftUI
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var currentNonce: String?

    private let screen = ScreenSize.current

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: 0.48, saturation: 0.72, brightness: 0.42),
                    Color(hue: 0.52, saturation: 0.60, brightness: 0.26),
                    Color(hue: 0.56, saturation: 0.50, brightness: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                        .padding(.bottom, screen.scale(32, compact: 20, large: 40))

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
        VStack(spacing: 14) {
            let iconSize = screen.scale(96, compact: 76, large: 108)
            ZStack {
                Circle()
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(width: iconSize, height: iconSize)
                Image(systemName: "bird.fill")
                    .font(.system(size: iconSize * 0.46, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse)
            }
            .padding(.top, screen.scale(56, compact: 32, large: 68))

            Text("BirdMap")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)

            Text("Citizen science, one sighting at a time")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(spacing: 16) {
            fieldsStack

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Text(error)
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.red.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            submitButton
            toggleButton

            HStack {
                Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
                Text("or").font(.caption).foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 8)
                Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
            }

            appleSignInButton
            googleSignInButton
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Fields

    private var fieldsStack: some View {
        VStack(spacing: 10) {
            glassField {
                Image(systemName: "envelope.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(.white)
                    .tint(.white)
            }

            if isRegistering {
                glassField {
                    Image(systemName: "person.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22)
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(.white)
                        .tint(.white)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            glassField {
                Image(systemName: "lock.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22)
                SecureField("Password", text: $password)
                    .foregroundStyle(.white)
                    .tint(.white)
            }
        }
        .animation(.spring(duration: 0.35), value: isRegistering)
    }

    @ViewBuilder
    private func glassField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Buttons

    private var submitButton: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: isRegistering ? "person.badge.plus" : "arrow.right.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                Text(isLoading ? "Please wait…" : (isRegistering ? "Create Account" : "Sign In"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Color.teal, in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isLoading)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }

    private var toggleButton: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) {
                isRegistering.toggle()
                error = nil
            }
        } label: {
            Text(isRegistering
                 ? "Already have an account? **Sign in**"
                 : "New here? **Create account**")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.top, 2)
    }

    private var appleSignInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = randomNonceString()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)
        } onCompletion: { result in
            handleAppleResult(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(isLoading)
    }

    private var googleSignInButton: some View {
        Button {
            Task { await signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                Text("G")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                Text("Sign in with Google")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
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

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else { error = "Apple sign-in failed"; return }
            let displayName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            Task {
                isLoading = true
                do {
                    try await FirebaseService.shared.signInWithApple(
                        idToken: idToken, nonce: nonce,
                        displayName: displayName.isEmpty ? nil : displayName
                    )
                    if let name = await FirebaseService.shared.fetchUsername() { env.saveUsername(name) }
                } catch { self.error = error.localizedDescription }
                isLoading = false
            }
        case .failure(let err):
            if (err as NSError).code != ASAuthorizationError.canceled.rawValue {
                error = err.localizedDescription
            }
        }
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

// MARK: - Nonce helpers

private func randomNonceString(length: Int = 32) -> String {
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length
    while remaining > 0 {
        (0..<16).map { _ -> UInt8 in var b: UInt8 = 0; _ = SecRandomCopyBytes(kSecRandomDefault, 1, &b); return b }
            .forEach { b in guard remaining > 0 else { return }; if b < charset.count { result.append(charset[Int(b)]); remaining -= 1 } }
    }
    return result
}

private func sha256(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
}
