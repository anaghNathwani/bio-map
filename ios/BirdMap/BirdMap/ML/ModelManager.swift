import Foundation
import CoreML
import ZIPFoundation
import FirebaseFirestore

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

    var isModelAvailable: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    /// Checks Firestore for a new active photo model version and downloads it if one exists.
    /// Safe to call on any concurrency context — uses async APIs internally.
    /// Models are published by `ml_pipeline/convert_photo_model.py` + `publish_model.py` to the
    /// `model_versions` Firestore collection and Supabase Storage (not Firebase Storage, which
    /// now requires a paid Blaze plan for any usage) — see docs/ML_PIPELINE.md.
    func checkForUpdate() async {
        do {
            // 1. Find the active photo model version
            let snap = try await Firestore.firestore().collection("model_versions")
                .whereField("mediaType", isEqualTo: "photo")
                .whereField("isActive", isEqualTo: true)
                .limit(to: 1)
                .getDocuments()
            guard let doc = snap.documents.first,
                  let version = doc.data()["version"] as? String,
                  let downloadURLString = doc.data()["downloadURL"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                print("[ModelManager] No active photo model published yet")
                return
            }

            // 2. Skip if we already have this version
            let stored = UserDefaults.standard.string(forKey: versionKey) ?? ""
            guard version != stored else {
                print("[ModelManager] Already at version \(version)")
                return
            }

            print("[ModelManager] Downloading model v\(version)…")

            // 3. Download the zip — a public Supabase Storage URL, no auth needed
            let (zipTemp, _) = try await URLSession.shared.download(from: downloadURL)

            // 4. Unzip into Documents — the zip root is BirdClassifier.mlpackage/
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dest = docs.appendingPathComponent("BirdClassifier.mlpackage")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.unzipItem(at: zipTemp, to: docs)

            // 5. Persist version and bust the classifier cache
            UserDefaults.standard.set(version, forKey: versionKey)
            cachedModel = nil
            cachedModelVersion = nil
            await BirdClassifier.shared.invalidateCache()
            print("[ModelManager] Model updated to v\(version)")
        } catch {
            print("[ModelManager] Update check failed: \(error)")
        }
    }
}
