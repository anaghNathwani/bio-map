import Foundation
import CoreML

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
}
