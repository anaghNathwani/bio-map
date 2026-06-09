import Foundation

/// Persists pending uploads so they survive app restarts when offline.
final class UploadQueue {
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
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }

    func enqueue(_ upload: PendingUpload) {
        var q = queue
        q.append(upload)
        queue = q
    }

    func flushIfNeeded() async {
        var remaining: [PendingUpload] = []
        for item in queue {
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
