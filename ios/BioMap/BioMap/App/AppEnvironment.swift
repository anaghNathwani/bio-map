import Foundation
import Combine
import FirebaseAuth

final class AppEnvironment: ObservableObject {
    @Published var user: FirebaseAuth.User?
    @Published var username: String?

    var isLoggedIn: Bool { user != nil }

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
        }
        username = UserDefaults.standard.string(forKey: "username")
    }

    deinit {
        if let handle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    func logout() {
        try? Auth.auth().signOut()
        username = nil
        UserDefaults.standard.removeObject(forKey: "username")
    }

    func saveUsername(_ name: String) {
        username = name
        UserDefaults.standard.set(name, forKey: "username")
    }
}
