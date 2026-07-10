import SwiftUI

@main
struct BirdMapApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            Group {
                if env.token == nil {
                    LoginView()
                } else {
                    ContentView()
                        .task {
                            await ModelManager.shared.checkForUpdate()
                            await UploadQueue.shared.flushIfNeeded()
                        }
                }
            }
            .environmentObject(env)
            .task {
                // Wire 401 handler to the live env instance on first launch
                APIClient.shared.environment = env
            }
        }
    }
}
