import Foundation
import Combine
import FirebaseAuth

/// Where a widget, lock-screen control or URL (`com.biomap.app://photo`) asks the app to land.
enum DeepLink: String {
    case photo, sound, map

    init?(url: URL) {
        guard url.scheme == "com.biomap.app", let host = url.host, let link = DeepLink(rawValue: host) else { return nil }
        self = link
    }
}

final class AppEnvironment: ObservableObject {
    @Published var user: FirebaseAuth.User?
    @Published var username: String?
    /// Set when the app is opened from a widget/control; ContentView consumes it once the user is signed in.
    @Published var pendingDeepLink: DeepLink?

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
