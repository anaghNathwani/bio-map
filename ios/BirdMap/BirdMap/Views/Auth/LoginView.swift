import SwiftUI

struct LoginView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isLoading = false
    @State private var error: String?

    private let screen = ScreenSize.current

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hue: 0.48, saturation: 0.6, brightness: 0.35), Color(hue: 0.52, saturation: 0.5, brightness: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        let iconSize = screen.scale(88, compact: 72, large: 100)
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.15))
                                .frame(width: iconSize, height: iconSize)
                            Image(systemName: "bird.fill")
                                .font(.system(size: iconSize * 0.5))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, screen.scale(48, compact: 28, large: 60))

                        Text("BirdMap")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)

                        Text("Citizen science, one sighting at a time")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, screen.scale(32, compact: 20, large: 40))

                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "envelope")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                TextField("Email", text: $email)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                            if isRegistering {
                                HStack {
                                    Image(systemName: "person")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    TextField("Username", text: $username)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            HStack {
                                Image(systemName: "lock")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                SecureField("Password", text: $password)
                            }
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .animation(.spring(duration: 0.3), value: isRegistering)

                        if let error {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(error)
                            }
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                }
                                Text(isLoading ? "Please wait…" : (isRegistering ? "Create Account" : "Sign In"))
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.teal, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                        }
                        .disabled(isLoading)

                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                isRegistering.toggle()
                                error = nil
                            }
                        } label: {
                            Text(isRegistering ? "Already have an account? **Sign in**" : "New here? **Create account**")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.top, 4)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func submit() async {
        isLoading = true
        error = nil
        do {
            let resp: APIClient.AuthResponse
            if isRegistering {
                resp = try await APIClient.shared.register(email: email, username: username, password: password)
            } else {
                resp = try await APIClient.shared.login(email: email, password: password)
            }
            env.username = resp.username
            env.token = resp.access_token
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
