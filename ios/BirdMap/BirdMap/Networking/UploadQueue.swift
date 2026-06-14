import Foundation

/// Persists pending uploads so they survive app restarts when offline.
/// Actor isolation ensures thread-safe queue access in async contexts.
actor UploadQueue {
    static let shared = UploadQueue()
    private let key = "pending_uploads"

    struct PendingUpload: Codable {
        let imageDataBase64: String
        let latitude: Double
        let longitude: Double
        let notes: String?
    }

    private var queue: [PendingUpload] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let q = try? JSONDecoder().decode([PendingUpload].self, from: data) else { return [] }
            return q
        }
        set {
            guard let encoded = try? JSONEncoder().encode(newValue) else {
                print("[UploadQueue] Failed to encode queue")
                return
            }
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func enqueue(_ upload: PendingUpload) {
        var q = queue
        q.append(upload)
        queue = q
    }

    func flushIfNeeded() async {
        let snapshot = queue
        guard !snapshot.isEmpty else { return }

        var remaining: [PendingUpload] = []
        for item in snapshot {
            guard let data = Data(base64Encoded: item.imageDataBase64) else { continue }
            do {
                _ = try await APIClient.shared.uploadSighting(
                    imageData: data,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    notes: item.notes
                )
            } catch {
                remaining.append(item)
            }
        }
        queue = remaining
    }
}
