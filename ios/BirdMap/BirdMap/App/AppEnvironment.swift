import Foundation
import Combine

final class AppEnvironment: ObservableObject {
    @Published var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    @Published var username: String? {
        didSet { UserDefaults.standard.set(username, forKey: "username") }
    }

    init() {
        token = UserDefaults.standard.string(forKey: "token")
        username = UserDefaults.standard.string(forKey: "username")
    }

    func logout() {
        token = nil
        username = nil
    }
}
