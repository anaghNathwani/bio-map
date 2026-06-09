import Foundation
import CoreML

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
        return try? MLModel(contentsOf: url)
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
        // Use Process on macOS; on iOS use ZipFoundation or a simple manual unzip.
        // For iOS production, add ZipFoundation via SPM. This is a placeholder.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-o", src.path, "-d", dest.path]
        try task.run()
        task.waitUntilExit()
    }
}
