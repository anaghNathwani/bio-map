import Foundation
import FirebaseFirestore
import CoreLocation

struct Sighting: Identifiable, Codable {
    @DocumentID var id: String?
    var latitude: Double
    var longitude: Double
    var photoURL: String?
    var thumbnailURL: String?
    var audioURL: String?
    var mediaType: String
    var notes: String?
    var aiSpeciesSuggestion: String?
    var aiConfidence: Double?
    var annotationCount: Int
    var topSpecies: String?
    var userId: String
    var username: String?
    var createdAt: Timestamp?

    var isAudio: Bool { mediaType == "audio" }
    var displaySpecies: String? { topSpecies ?? aiSpeciesSuggestion }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, notes, username
        case photoURL = "photoURL"
        case thumbnailURL = "thumbnailURL"
        case audioURL = "audioURL"
        case mediaType = "mediaType"
        case aiSpeciesSuggestion = "aiSpeciesSuggestion"
        case aiConfidence = "aiConfidence"
        case annotationCount = "annotationCount"
        case topSpecies = "topSpecies"
        case userId = "userId"
        case createdAt = "createdAt"
    }
}

struct SightingDetail: Identifiable {
    var id: String
    var latitude: Double
    var longitude: Double
    var photoURL: String?
    var thumbnailURL: String?
    var audioURL: String?
    var photoFallbackURL: String?
    var audioFallbackURL: String?
    var mediaType: String
    var notes: String?
    var aiSpeciesSuggestion: String?
    var aiConfidence: Double?
    /// Species detected beyond the primary aiSpeciesSuggestion (BirdNET can
    /// report several distinct calls in one recording) — see live_poll.py's
    /// aiSpeciesSuggestions field. Does not include the primary entry.
    var additionalSpecies: [BirdCandidate]
    var annotations: [AnnotationItem]
    /// True once BirdNET has run on this recording (on-device at submission, or
    /// by the server job later) — regardless of whether it heard a bird.
    var aiAnalyzed: Bool = false

    var isAudio: Bool { mediaType == "audio" }
    var displaySpecies: String? { aiSpeciesSuggestion }
}

struct AnnotationItem: Identifiable, Codable {
    @DocumentID var id: String?
    var species: String
    var confidence: Double
    var behavior: String?
    var agePlumage: String?
    var username: String
    var userId: String
    var createdAt: Timestamp?
    /// Set when this annotation came from the post-upload AI review flow:
    /// "confirmed" (user tapped Right), "rejected" (Wrong), or "unsure".
    var reviewOfAI: String?
    /// Legacy: written by the old server-side moderation pass (ml_pipeline/live_poll.py)
    /// on annotations made before moderation moved on-device. Nothing reads it
    /// any more — the "Flagged" badge is decided on-device by AnnotationModerator.
    var moderation: String?
    var moderationScore: Double?

    enum CodingKeys: String, CodingKey {
        case id, species, confidence, behavior, username, moderation
        case agePlumage = "agePlumage"
        case userId = "userId"
        case createdAt = "createdAt"
        case reviewOfAI = "reviewOfAI"
        case moderationScore = "moderationScore"
    }
}

struct LeaderboardEntry: Identifiable {
    var id: String
    var username: String
    var annotationCount: Int
}
