import Foundation

/// Persists pending uploads across app restarts.
/// Stores image file paths instead of base64 strings to avoid 33% size
/// inflation and the CPU cost of encoding/decoding large JPEG data.
actor UploadQueue {
    static let shared = UploadQueue()
    private let key = "pending_uploads"

    struct PendingUpload: Codable {
        let imagePath: String        // absolute path to JPEG in caches directory
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
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: item.imagePath)) else {
                // File missing — discard silently
                continue
            }
            do {
                _ = try await APIClient.shared.uploadSighting(
                    imageData: data,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    notes: item.notes
                )
                // Delete the temp file on success
                try? FileManager.default.removeItem(atPath: item.imagePath)
            } catch {
                remaining.append(item)
            }
        }
        queue = remaining
    }
}
