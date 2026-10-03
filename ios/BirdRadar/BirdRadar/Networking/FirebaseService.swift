import Foundation
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import UIKit
import CoreLocation

// Central Firebase service — every data operation, media blobs included, goes
// through Firestore/Auth directly, no backend. Photo/audio bytes are
// compressed client-side and embedded as base64 data URIs directly in the
// sighting document (primary), the same pattern used in
// github.com/ishanvi-dekate/team-efficient-epp (Profile.jsx's avatar upload,
// ChatBot.jsx's imageToBase64) to avoid Firebase Storage's Blaze billing
// requirement entirely — genuinely free, no card. See docs/DEPLOYMENT.md.
// The same bytes are also uploaded to Supabase Storage as a best-effort
// fallback copy (SupabaseStorage.uploadFallback) — if that fails, the sighting
// still saves fine with just the primary embedded copy.
private extension UIImage {
    /// Aspect-preserving downscale, no-op if already within bounds.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

final class FirebaseService {
    static let shared = FirebaseService()
    let db = Firestore.firestore()

    private init() {}

    var currentUID: String? { Auth.auth().currentUser?.uid }

    // MARK: - Auth

    func register(email: String, username: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        try await db.collection("users").document(result.user.uid).setData([
            "username": username,
            "email": email,
            "annotationCount": 0,
            "createdAt": Timestamp(),
        ])
    }

    func login(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    // MARK: - Social Sign-In

    func signInWithGoogle() async throws {
        guard let rootVC = await UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController
        else { throw AppError.notLoggedIn }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else { throw AppError.notLoggedIn }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        let uid = authResult.user.uid
        let email = authResult.user.email ?? ""
        let name = authResult.user.displayName ?? email.components(separatedBy: "@").first ?? "User"
        let ref = db.collection("users").document(uid)
        let doc = try? await ref.getDocument()
        if doc?.exists != true {
            try await ref.setData([
                "username": name,
                "email": email,
                "annotationCount": 0,
                "createdAt": Timestamp(),
            ])
        }
    }


    func fetchUsername() async -> String? {
        guard let uid = currentUID else { return nil }
        let doc = try? await db.collection("users").document(uid).getDocument()
        return doc?.data()?["username"] as? String
    }

    func updateUsername(_ newUsername: String) async throws {
        guard let uid = currentUID else { throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]) }
        try await db.collection("users").document(uid).setData(["username": newUsername], merge: true)
    }

    // MARK: - Media "upload" (compressed base64 embedded in the Firestore doc)

    /// Firestore rejects a single string field once its encoded size exceeds
    /// a hard cap just under 1 MiB (confirmed live: "value of property
    /// photoURL is longer than 1048487 bytes"). A single fixed
    /// resize+quality pass isn't safe — some photos (more detail/noise) don't
    /// compress as well as others and blow past that cap even after
    /// downscaling to 1600px at 0.85 quality, which is what this used to do
    /// unconditionally. compressForEmbedding instead iterates quality then
    /// dimension until the JPEG actually fits under maxRawBytes, so the
    /// upload can't fail this way regardless of the source photo.
    private static let maxEncodedDimension: CGFloat = 1600
    private static let jpegQuality: CGFloat = 0.85
    /// Raw JPEG byte budget before base64 (~4/3 inflation) is applied —
    /// comfortably under the ~1,048,487-byte field cap with room for the
    /// sighting doc's other fields alongside it.
    private static let maxRawBytes = 700_000

    private func compressForEmbedding(_ image: UIImage) -> Data? {
        var dimension = Self.maxEncodedDimension
        var quality = Self.jpegQuality
        for _ in 0..<8 {
            if let jpeg = image.resized(maxDimension: dimension).jpegData(compressionQuality: quality),
               jpeg.count <= Self.maxRawBytes {
                return jpeg
            }
            if quality > 0.35 {
                quality -= 0.15
            } else {
                dimension *= 0.75
            }
        }
        // Last-ditch minimal attempt — a low-quality thumbnail beats a failed upload.
        return image.resized(maxDimension: 640).jpegData(compressionQuality: 0.25)
    }

    func uploadImage(_ data: Data, sightingID: String) async throws -> (photoURL: String, thumbnailURL: String?, fallbackURL: String?) {
        guard Auth.auth().currentUser != nil else { throw AppError.notLoggedIn }
        guard let image = UIImage(data: data) else { throw AppError.invalidImage }
        guard let jpeg = compressForEmbedding(image) else { throw AppError.invalidImage }
        let dataURI = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        let fallbackURL = await SupabaseStorage.uploadFallback(
            jpeg, path: "sightings/\(sightingID)/photo.jpg", contentType: "image/jpeg"
        )
        return (dataURI, nil, fallbackURL)
    }

    func uploadAudio(_ data: Data, sightingID: String, filename: String) async throws -> (audioURL: String, fallbackURL: String?) {
        guard Auth.auth().currentUser != nil else { throw AppError.notLoggedIn }
        let dataURI = "data:audio/mp4;base64,\(data.base64EncodedString())"
        let fallbackURL = await SupabaseStorage.uploadFallback(
            data, path: "sightings/\(sightingID)/\(filename)", contentType: "audio/mp4"
        )
        return (dataURI, fallbackURL)
    }

    // MARK: - Sightings

    func createSighting(
        photoURL: String?,
        thumbnailURL: String?,
        audioURL: String?,
        photoFallbackURL: String? = nil,
        audioFallbackURL: String? = nil,
        mediaType: String,
        latitude: Double,
        longitude: Double,
        notes: String?,
        aiSpecies: String?,
        aiConfidence: Double?,
        aiAdditionalSpecies: [BirdCandidate] = [],
        aiAnalyzed: Bool = false
    ) async throws -> String {
        guard let uid = currentUID else { throw AppError.notLoggedIn }
        let username = await fetchUsername() ?? "unknown"
        let ref = db.collection("sightings").document()
        var data: [String: Any] = [
            "userId": uid,
            "username": username,
            "mediaType": mediaType,
            "latitude": latitude,
            "longitude": longitude,
            "annotationCount": 0,
            "createdAt": Timestamp(),
        ]
        if let v = photoURL { data["photoURL"] = v }
        if let v = thumbnailURL { data["thumbnailURL"] = v }
        if let v = audioURL { data["audioURL"] = v }
        if let v = photoFallbackURL { data["photoFallbackURL"] = v }
        if let v = audioFallbackURL { data["audioFallbackURL"] = v }
        if let v = notes { data["notes"] = v }
        if let v = aiSpecies { data["aiSpeciesSuggestion"] = v }
        if let v = aiConfidence { data["aiConfidence"] = v }
        // Set when the app already ran BirdNET on-device (even if it heard
        // nothing), so ml_pipeline/live_poll.py doesn't redo the same clip.
        if aiAnalyzed { data["aiAnalyzedAt"] = Timestamp() }
        // Mirrors live_poll.py's format so fetchSightingDetail's parsing
        // (which drops element 0, the primary) works for photos too.
        if let species = aiSpecies {
            let primary: [String: Any] = ["species": species, "confidence": aiConfidence ?? 0]
            let extras = aiAdditionalSpecies.map { ["species": $0.species, "confidence": $0.confidence] }
            data["aiSpeciesSuggestions"] = [primary] + extras
        }

        try await ref.setData(data)
        return ref.documentID
    }

    func fetchSightings(region: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)? = nil) async throws -> [Sighting] {
        var query: Query = db.collection("sightings").limit(to: 300)
        if let r = region {
            // Firestore requires the first orderBy to match a range-filtered
            // field, so this branch orders by latitude instead of createdAt
            // — the createdAt ordering is restored client-side below. (The
            // longitude bound can't be range-filtered server-side alongside
            // latitude — Firestore only allows that on one field — so it's
            // applied client-side too, same as before.)
            query = query
                .whereField("latitude", isGreaterThan: r.minLat)
                .whereField("latitude", isLessThan: r.maxLat)
                .order(by: "latitude")
        } else {
            query = query.order(by: "createdAt", descending: true)
        }
        let snap = try await query.getDocuments()
        var sightings = snap.documents.compactMap { try? $0.data(as: Sighting.self) }
        if let r = region {
            sightings = sightings
                .filter { $0.longitude >= r.minLng && $0.longitude <= r.maxLng }
                .sorted { ($0.createdAt?.dateValue() ?? .distantPast) > ($1.createdAt?.dateValue() ?? .distantPast) }
        }
        return sightings
    }

    /// Loads specific sightings by id (used for the user's saved list, which
    /// shouldn't be limited to whatever's inside the current map viewport).
    /// Ids that no longer exist or fail to load are skipped.
    func fetchSightings(ids: [String]) async -> [Sighting] {
        let db = self.db
        return await withTaskGroup(of: Sighting?.self) { group in
            for id in ids {
                group.addTask { try? await db.collection("sightings").document(id).getDocument(as: Sighting.self) }
            }
            var result: [Sighting] = []
            for await sighting in group { if let sighting { result.append(sighting) } }
            return result.sorted {
                ($0.createdAt?.dateValue() ?? .distantPast) > ($1.createdAt?.dateValue() ?? .distantPast)
            }
        }
    }

    func fetchSightingDetail(id: String) async throws -> SightingDetail {
        let doc = try await db.collection("sightings").document(id).getDocument()
        guard let data = doc.data() else { throw AppError.notFound }

        let annSnap = try await db.collection("sightings").document(id)
            .collection("annotations").order(by: "createdAt", descending: true).getDocuments()
        let annotations = annSnap.documents.compactMap { try? $0.data(as: AnnotationItem.self) }

        // Drop the first entry — it's the same bird as aiSpeciesSuggestion
        // above, already shown as the primary result; this is the rest.
        let additionalSpecies: [BirdCandidate] = (data["aiSpeciesSuggestions"] as? [[String: Any]] ?? [])
            .dropFirst()
            .compactMap { entry in
                guard let sp = entry["species"] as? String else { return nil }
                return BirdCandidate(species: sp, confidence: entry["confidence"] as? Double ?? 0)
            }

        return SightingDetail(
            id: id,
            latitude: data["latitude"] as? Double ?? 0,
            longitude: data["longitude"] as? Double ?? 0,
            photoURL: data["photoURL"] as? String,
            thumbnailURL: data["thumbnailURL"] as? String,
            audioURL: data["audioURL"] as? String,
            photoFallbackURL: data["photoFallbackURL"] as? String,
            audioFallbackURL: data["audioFallbackURL"] as? String,
            mediaType: data["mediaType"] as? String ?? "photo",
            notes: data["notes"] as? String,
            aiSpeciesSuggestion: data["aiSpeciesSuggestion"] as? String,
            aiConfidence: data["aiConfidence"] as? Double,
            additionalSpecies: additionalSpecies,
            annotations: annotations,
            aiAnalyzed: data["aiAnalyzedAt"] != nil
        )
    }

    func submitAnnotation(sightingID: String, species: String, confidence: Double, behavior: String?, agePlumage: String?, reviewOfAI: String? = nil) async throws {
        guard let uid = currentUID else { throw AppError.notLoggedIn }
        let username = await fetchUsername() ?? "unknown"

        var data: [String: Any] = [
            "userId": uid,
            "username": username,
            "species": species,
            "confidence": confidence,
            "createdAt": Timestamp(),
        ]
        if let v = behavior { data["behavior"] = v }
        if let v = agePlumage { data["agePlumage"] = v }
        if let v = reviewOfAI { data["reviewOfAI"] = v }

        try await db.collection("sightings").document(sightingID)
            .collection("annotations").addDocument(data: data)

        // Update annotation count + top species on sighting (best-effort).
        // An "unsure" review carries no species — leave topSpecies as-is rather
        // than blanking it out.
        var sightingUpdate: [String: Any] = ["annotationCount": FieldValue.increment(Int64(1))]
        if !species.isEmpty { sightingUpdate["topSpecies"] = species }
        try? await db.collection("sightings").document(sightingID).updateData(sightingUpdate)

        // Increment user's annotation count
        try? await db.collection("users").document(uid).updateData([
            "annotationCount": FieldValue.increment(Int64(1)),
        ])
    }

    // MARK: - Leaderboard

    func fetchLeaderboard(limit: Int = 50) async throws -> [LeaderboardEntry] {
        let snap = try await db.collection("users")
            .order(by: "annotationCount", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { doc in
            guard let username = doc.data()["username"] as? String,
                  let count = doc.data()["annotationCount"] as? Int else { return nil }
            return LeaderboardEntry(id: doc.documentID, username: username, annotationCount: count)
        }
    }
}

enum AppError: LocalizedError {
    case notLoggedIn, notFound, invalidImage

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "You must be logged in"
        case .notFound: return "Not found"
        case .invalidImage: return "Could not process photo"
        }
    }
}
