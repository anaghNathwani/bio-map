import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct BioMapApp: App {
    @StateObject private var env = AppEnvironment()
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()

        // Configure Google Sign-In with Firebase client ID
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        Task {
            await ModelManager.shared.checkForUpdate()
        }

        // Build the bird-name lookup the annotation moderator uses now, off the
        // main thread, so the first annotation card doesn't pay for it.
        Task.detached(priority: .utility) { _ = AnnotationModerator.shared }

        Task {
            await UploadQueue.shared.flushIfNeeded { item in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: item.imagePath)) else { return }
                let sightingID = UUID().uuidString
                let (photoURL, thumbURL, fallbackURL) = try await FirebaseService.shared.uploadImage(data, sightingID: sightingID)
                _ = try await FirebaseService.shared.createSighting(
                    photoURL: photoURL,
                    thumbnailURL: thumbURL,
                    audioURL: nil,
                    photoFallbackURL: fallbackURL,
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
            // Lock-screen control taps (ControlIntents.swift): route to the camera / recorder.
            .onReceive(NotificationCenter.default.publisher(for: ControlRoute.requested)) { _ in takeControlRoute() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { takeControlRoute() } }
            .onAppear { takeControlRoute() }
            .onOpenURL { url in
                if let link = DeepLink(url: url) {
                    env.pendingDeepLink = link
                } else {
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
            }
        }
    }

    private func takeControlRoute() {
        if let route = ControlRoute.takePending(), let link = DeepLink(rawValue: route) {
            env.pendingDeepLink = link
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
