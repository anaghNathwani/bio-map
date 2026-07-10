import Foundation
import Combine

final class AppEnvironment: ObservableObject {
    @Published var token: String? {
        didSet {
            if let token { KeychainHelper.save(token, for: "auth_token") }
            else { KeychainHelper.delete(for: "auth_token") }
        }
    }
    @Published var username: String? {
        didSet {
            if let username { KeychainHelper.save(username, for: "username") }
            else { KeychainHelper.delete(for: "username") }
        }
    }

    init() {
        token = KeychainHelper.load(for: "auth_token")
        username = KeychainHelper.load(for: "username")
    }

    func logout() {
        token = nil
        username = nil
    }

    /// Called when the API returns 401 — token is expired or revoked.
    func handleUnauthorized() {
        DispatchQueue.main.async { self.logout() }
    }
}
