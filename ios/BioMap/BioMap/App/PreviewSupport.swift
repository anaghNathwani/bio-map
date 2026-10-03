import SwiftUI
import FirebaseCore

/// Helpers for Xcode canvas previews. Previews don't run `BioMapApp.init`, so
/// Firebase has to be configured here before any view touches Auth/Firestore.
enum PreviewSupport {
    static func configureFirebase() {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
    }

    static let sighting = Sighting(
        id: "preview",
        latitude: 37.7749,
        longitude: -122.4194,
        photoURL: nil,
        thumbnailURL: nil,
        audioURL: nil,
        mediaType: "photo",
        notes: "Feeding at the bird bath",
        aiSpeciesSuggestion: "American Robin",
        aiConfidence: 0.92,
        annotationCount: 2,
        topSpecies: nil,
        userId: "preview-user",
        username: "birder",
        createdAt: nil
    )
}

/// Wraps a preview so Firebase is configured before its content is built.
struct FirebasePreview<Content: View>: View {
    private let content: Content

    init(@ViewBuilder _ content: () -> Content) {
        PreviewSupport.configureFirebase()
        self.content = content()
    }

    var body: some View { content }
}
