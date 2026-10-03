import Foundation

actor UploadQueue {
    static let shared = UploadQueue()
    private let key = "pending_uploads"

    struct PendingUpload: Codable {
        let imagePath: String
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
            guard let encoded = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func enqueue(_ upload: PendingUpload) {
        var q = queue
        q.append(upload)
        queue = q
    }

    // Caller provides the actual upload logic so this actor stays Firebase-free.
    func flushIfNeeded(uploader: (PendingUpload) async throws -> Void) async {
        let snapshot = queue
        guard !snapshot.isEmpty else { return }

        var remaining: [PendingUpload] = []
        for item in snapshot {
            do {
                try await uploader(item)
                try? FileManager.default.removeItem(atPath: item.imagePath)
            } catch {
                remaining.append(item)
            }
        }
        queue = remaining
    }
}
