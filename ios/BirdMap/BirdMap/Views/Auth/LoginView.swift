import SwiftUI

struct LoginView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if isRegistering {
                        TextField("Username", text: $username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    SecureField("Password", text: $password)
                }

                if let error {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                Section {
                    Button(isLoading ? "Please wait..." : (isRegistering ? "Create Account" : "Sign In")) {
                        Task { await submit() }
                    }
                    .disabled(isLoading)
                }

                Section {
                    Button(isRegistering ? "Already have an account? Sign in" : "New here? Create account") {
                        isRegistering.toggle()
                        error = nil
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("BirdMap")
        }
    }

    private func submit() async {
        isLoading = true
        error = nil
        do {
            let token: String
            if isRegistering {
                token = try await APIClient.shared.register(email: email, username: username, password: password)
                env.username = username
            } else {
                token = try await APIClient.shared.login(email: email, password: password)
            }
            env.token = token
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
