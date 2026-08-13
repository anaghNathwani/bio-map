import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn
import UIKit
import CoreLocation

// Central Firebase service — replaces APIClient for all data operations.
final class FirebaseService {
    static let shared = FirebaseService()
    let db = Firestore.firestore()
    let storage = Storage.storage()

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

    func signInWithApple(idToken: String, nonce: String, displayName: String?) async throws {
        let credential = OAuthProvider.credential(withProviderID: "apple.com", idToken: idToken, rawNonce: nonce)
        let result = try await Auth.auth().signIn(with: credential)
        // Ensure user document exists
        let uid = result.user.uid
        let email = result.user.email ?? ""
        let name = displayName ?? result.user.displayName ?? email.components(separatedBy: "@").first ?? "User"
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

    // MARK: - Storage Upload

    func uploadImage(_ data: Data, sightingID: String) async throws -> (photoURL: String, thumbnailURL: String?) {
        let ref = storage.reference().child("sightings/\(sightingID)/photo.jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: meta)
        let url = try await ref.downloadURL()

        // Thumbnail: resize on-device
        var thumbURL: String? = nil
        if let img = UIImage(data: data), let thumb = img.thumbnail(maxSize: 400),
           let thumbData = thumb.jpegData(compressionQuality: 0.75) {
            let thumbRef = storage.reference().child("sightings/\(sightingID)/thumbnail.jpg")
            _ = try? await thumbRef.putDataAsync(thumbData, metadata: meta)
            thumbURL = try? await thumbRef.downloadURL().absoluteString
        }

        return (url.absoluteString, thumbURL)
    }

    func uploadAudio(_ data: Data, sightingID: String, filename: String) async throws -> String {
        let ext = filename.hasSuffix(".m4a") ? "m4a" : "m4a"
        let ref = storage.reference().child("sightings/\(sightingID)/audio.\(ext)")
        let meta = StorageMetadata()
        meta.contentType = "audio/mp4"
        _ = try await ref.putDataAsync(data, metadata: meta)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    // MARK: - Sightings

    func createSighting(
        photoURL: String?,
        thumbnailURL: String?,
        audioURL: String?,
        mediaType: String,
        latitude: Double,
        longitude: Double,
        notes: String?,
        aiSpecies: String?,
        aiConfidence: Double?
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
        if let v = notes { data["notes"] = v }
        if let v = aiSpecies { data["aiSpeciesSuggestion"] = v }
        if let v = aiConfidence { data["aiConfidence"] = v }

        try await ref.setData(data)
        return ref.documentID
    }

    func fetchSightings(region: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)? = nil) async throws -> [Sighting] {
        var query: Query = db.collection("sightings").order(by: "createdAt", descending: true).limit(to: 300)
        if let r = region {
            query = query.whereField("latitude", isGreaterThan: r.minLat).whereField("latitude", isLessThan: r.maxLat)
        }
        let snap = try await query.getDocuments()
        var sightings = snap.documents.compactMap { try? $0.data(as: Sighting.self) }
        if let r = region {
            sightings = sightings.filter { $0.longitude >= r.minLng && $0.longitude <= r.maxLng }
        }
        return sightings
    }

    func fetchSightingDetail(id: String) async throws -> SightingDetail {
        let doc = try await db.collection("sightings").document(id).getDocument()
        guard let data = doc.data() else { throw AppError.notFound }

        let annSnap = try await db.collection("sightings").document(id)
            .collection("annotations").order(by: "createdAt", descending: true).getDocuments()
        let annotations = annSnap.documents.compactMap { try? $0.data(as: AnnotationItem.self) }

        return SightingDetail(
            id: id,
            latitude: data["latitude"] as? Double ?? 0,
            longitude: data["longitude"] as? Double ?? 0,
            photoURL: data["photoURL"] as? String,
            thumbnailURL: data["thumbnailURL"] as? String,
            audioURL: data["audioURL"] as? String,
            mediaType: data["mediaType"] as? String ?? "photo",
            notes: data["notes"] as? String,
            aiSpeciesSuggestion: data["aiSpeciesSuggestion"] as? String,
            aiConfidence: data["aiConfidence"] as? Double,
            annotations: annotations
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
    case notLoggedIn, notFound

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "You must be logged in"
        case .notFound: return "Not found"
        }
    }
}

// MARK: - UIImage thumbnail helper
private extension UIImage {
    func thumbnail(maxSize: CGFloat) -> UIImage? {
        let scale = maxSize / max(size.width, size.height)
        guard scale < 1 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
