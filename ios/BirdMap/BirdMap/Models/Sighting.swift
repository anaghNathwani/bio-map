import Foundation

struct Sighting: Identifiable, Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let photoURL: String
    let thumbnailURL: String?
    let audioURL: String?
    let mediaType: String?
    let notes: String?
    let aiSpeciesSuggestion: String?
    let aiConfidence: Double?
    let annotationCount: Int
    let topSpecies: String?

    var isAudio: Bool { mediaType == "audio" }
    var displaySpecies: String? { topSpecies ?? aiSpeciesSuggestion }

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, notes
        case photoURL = "photo_url"
        case thumbnailURL = "thumbnail_url"
        case audioURL = "audio_url"
        case mediaType = "media_type"
        case aiSpeciesSuggestion = "ai_species_suggestion"
        case aiConfidence = "ai_confidence"
        case annotationCount = "annotation_count"
        case topSpecies = "top_species"
    }
}

struct SightingDetail: Identifiable, Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let photoURL: String
    let thumbnailURL: String?
    let audioURL: String?
    let mediaType: String?
    let notes: String?
    let aiSpeciesSuggestion: String?
    let aiConfidence: Double?
    let annotations: [AnnotationItem]

    var isAudio: Bool { mediaType == "audio" }
    var displaySpecies: String? { aiSpeciesSuggestion }

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, notes, annotations
        case photoURL = "photo_url"
        case thumbnailURL = "thumbnail_url"
        case audioURL = "audio_url"
        case mediaType = "media_type"
        case aiSpeciesSuggestion = "ai_species_suggestion"
        case aiConfidence = "ai_confidence"
    }
}

struct AnnotationItem: Identifiable, Codable {
    let id: UUID
    let species: String
    let confidence: Double
    let behavior: String?
    let agePlumage: String?
    let username: String

    enum CodingKeys: String, CodingKey {
        case id, species, confidence, behavior, username
        case agePlumage = "age_plumage"
    }
}

struct LeaderboardEntry: Identifiable, Codable {
    var id: String { username }
    let username: String
    let annotationCount: Int

    enum CodingKeys: String, CodingKey {
        case username
        case annotationCount = "annotation_count"
    }
}

struct ModelVersionInfo: Codable {
    let version: String
    let numClasses: Int
    let accuracy: Double?

    enum CodingKeys: String, CodingKey {
        case version, accuracy
        case numClasses = "num_classes"
    }
}
