import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct BirdMapApp: App {
    @StateObject private var env = AppEnvironment()
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    init() {
        FirebaseApp.configure()

        // Configure Google Sign-In with Firebase client ID
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        Task {
            await ModelManager.shared.checkForUpdate()
        }

        Task {
            await UploadQueue.shared.flushIfNeeded { item in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: item.imagePath)) else { return }
                let sightingID = UUID().uuidString
                let (photoURL, thumbURL) = try await FirebaseService.shared.uploadImage(data, sightingID: sightingID)
                _ = try await FirebaseService.shared.createSighting(
                    photoURL: photoURL,
                    thumbnailURL: thumbURL,
                    audioURL: nil,
                    mediaType: "photo",
                    latitude: item.latitude,
                    longitude: item.longitude,
                    notes: item.notes,
                    aiSpecies: nil,
                    aiConfidence: nil
                )
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()
                if env.isLoggedIn {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(env)
            .preferredColorScheme(colorScheme(for: appearanceMode))
        }
    }

    private func colorScheme(for mode: String) -> ColorScheme? {
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
