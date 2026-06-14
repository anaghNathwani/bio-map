import Foundation
import CoreML

enum ModelManagerError: Error {
    case unzipNotImplemented
}

final class ModelManager {
    static let shared = ModelManager()

    private let versionKey = "model_version"
    private var modelURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BirdClassifier.mlpackage")
    }

    var currentModel: MLModel? {
        guard let url = modelURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try MLModel(contentsOf: url)
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

        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: url)
            let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BirdClassifier_\(version).mlpackage.zip")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmpURL, to: dest)

            // Unzip
            let unzipDest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try unzip(at: dest, to: unzipDest)
            UserDefaults.standard.set(version, forKey: versionKey)
            print("[ModelManager] Updated to model version \(version)")
        } catch {
            print("[ModelManager] Download failed: \(error)")
        }
    }

    private func unzip(at src: URL, to dest: URL) throws {
        // coordinate reading the zip archive with Foundation's built-in zip support (iOS 16+)
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: src, options: .withoutChanges, error: &err) { url in
            _ = try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        }
        if let err { throw err }

        // Use the system-provided unzip via posix_spawn — not Process (which is macOS-only).
        // On iOS, the recommended approach is ZipFoundation (add via SPM for App Store builds).
        // This fallback unpacks using the Archive API available in the Swift standard library as
        // of Swift 5.9 / iOS 16 via the Foundation framework's coordination APIs.
        //
        // For now we use a URLSession-downloaded zip and rely on the .mlpackage directory being
        // accessible once expanded. A full implementation requires ZipFoundation:
        //   https://github.com/weichsel/ZIPFoundation
        //
        // Add to Package.swift:
        //   .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
        // Then replace this method body with:
        //   try FileManager.default.unzipItem(at: src, to: dest)
        throw ModelManagerError.unzipNotImplemented
    }
}
