import Foundation
import CoreML
import ZIPFoundation

final class ModelManager {
    static let shared = ModelManager()

    private let versionKey = "model_version"
    private var cachedModel: MLModel?
    private var cachedModelVersion: String?

    private var modelURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BirdClassifier.mlpackage")
    }

    // Cached — loads from disk once per version, not on every access.
    var currentModel: MLModel? {
        let version = UserDefaults.standard.string(forKey: versionKey) ?? ""
        if let cached = cachedModel, cachedModelVersion == version {
            return cached
        }
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return nil }
        do {
            let model = try MLModel(contentsOf: modelURL)
            cachedModel = model
            cachedModelVersion = version
            return model
        } catch {
            print("[ModelManager] Failed to load model: \(error)")
            return nil
        }
    }

    func checkForUpdate() async {
        guard let remote = try? await APIClient.shared.modelVersion() else { return }
        let stored = UserDefaults.standard.string(forKey: versionKey) ?? ""
        guard remote.version != stored else { return }
        await downloadModel(version: remote.version)
    }

    private func downloadModel(version: String) async {
        guard let urlStr = try? await APIClient.shared.modelDownloadURL(),
              let url = URL(string: urlStr) else { return }

        // Use a background URLSession so the download survives app backgrounding
        // and doesn't need to restart if interrupted.
        let config = URLSessionConfiguration.background(withIdentifier: "com.birdmap.modeldownload.\(version)")
        config.isDiscretionary = true          // let the OS pick an efficient time
        config.sessionSendsLaunchEvents = false // no need to relaunch for model updates

        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: url)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let zipDest = docs.appendingPathComponent("BirdClassifier_\(version).mlpackage.zip")
            try? FileManager.default.removeItem(at: zipDest)
            try FileManager.default.moveItem(at: tmpURL, to: zipDest)

            try unzip(at: zipDest, to: docs)
            try? FileManager.default.removeItem(at: zipDest) // clean up zip after extraction

            // Invalidate caches so next inference picks up the new model
            cachedModel = nil
            cachedModelVersion = nil
            BirdClassifier.shared.invalidateCache()

            UserDefaults.standard.set(version, forKey: versionKey)
            print("[ModelManager] Updated to model version \(version)")
        } catch {
            print("[ModelManager] Download failed: \(error)")
        }
    }

    private func unzip(at src: URL, to dest: URL) throws {
        try FileManager.default.unzipItem(at: src, to: dest)
    }
}
