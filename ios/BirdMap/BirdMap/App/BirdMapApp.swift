import SwiftUI

@main
struct BirdMapApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            if env.token == nil {
                LoginView()
                    .environmentObject(env)
            } else {
                ContentView()
                    .environmentObject(env)
                    .task { await ModelManager.shared.checkForUpdate() }
            }
        }
    }
}
