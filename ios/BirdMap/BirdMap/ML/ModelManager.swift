import Foundation
import CoreML
import ZIPFoundation
import FirebaseFirestore

final class ModelManager {
    static let shared = ModelManager()

    private let versionKey = "model_version"
    private var cachedModel: MLModel?
    private var cachedModelVersion: String?

    /// Tier 2 photo object detector (YOLOv3-Tiny/COCO, see BirdDetector.swift)
    /// — separate model, separate cache, separate download, optional (Tier 1
    /// saliency in MultiBirdDetector.swift is used whenever this isn't
    /// available yet).
    private let detectorVersionKey = "model_detector_version"
    private var cachedDetectorModel: MLModel?
    private var cachedDetectorModelVersion: String?

    private var modelURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BirdClassifier.mlpackage")
    }

    private var detectorModelURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BirdDetector.mlmodel")
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

    var currentDetectorModel: MLModel? {
        let version = UserDefaults.standard.string(forKey: detectorVersionKey) ?? ""
        if let cached = cachedDetectorModel, cachedDetectorModelVersion == version {
            return cached
        }
        guard FileManager.default.fileExists(atPath: detectorModelURL.path) else { return nil }
        do {
            let model = try MLModel(contentsOf: detectorModelURL)
            cachedDetectorModel = model
            cachedDetectorModelVersion = version
            return model
        } catch {
            print("[ModelManager] Failed to load detector model: \(error)")
            return nil
        }
    }

    var isDetectorModelAvailable: Bool {
        FileManager.default.fileExists(atPath: detectorModelURL.path)
    }

    /// Checks Firestore for new active model versions (photo classifier and,
    /// if published, the photo object detector) and downloads whichever have
    /// changed. Safe to call on any concurrency context — uses async APIs
    /// internally. Models are published by `ml_pipeline/convert_photo_model.py`
    /// / `convert_bird_detector_model.py` + `publish_model.py` to the
    /// `model_versions` Firestore collection and Supabase Storage (not
    /// Firebase Storage, which now requires a paid Blaze plan for any usage)
    /// — see docs/ML_PIPELINE.md.
    func checkForUpdate() async {
        await checkForClassifierUpdate()
        await checkForDetectorUpdate()
    }

    private func checkForClassifierUpdate() async {
        do {
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

            let stored = UserDefaults.standard.string(forKey: versionKey) ?? ""
            guard version != stored else {
                print("[ModelManager] Classifier already at version \(version)")
                return
            }

            print("[ModelManager] Downloading classifier model v\(version)…")
            // Zip root is BirdClassifier.mlpackage/ — a public Supabase Storage URL, no auth needed.
            let (zipTemp, _) = try await URLSession.shared.download(from: downloadURL)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: modelURL)
            try FileManager.default.unzipItem(at: zipTemp, to: docs)

            UserDefaults.standard.set(version, forKey: versionKey)
            cachedModel = nil
            cachedModelVersion = nil
            await BirdClassifier.shared.invalidateCache()
            print("[ModelManager] Classifier updated to v\(version)")
        } catch {
            print("[ModelManager] Classifier update check failed: \(error)")
        }
    }

    private func checkForDetectorUpdate() async {
        do {
            let snap = try await Firestore.firestore().collection("model_versions")
                .whereField("mediaType", isEqualTo: "photo_detector")
                .whereField("isActive", isEqualTo: true)
                .limit(to: 1)
                .getDocuments()
            guard let doc = snap.documents.first,
                  let version = doc.data()["version"] as? String,
                  let downloadURLString = doc.data()["downloadURL"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                print("[ModelManager] No active photo detector model published yet")
                return
            }

            let stored = UserDefaults.standard.string(forKey: detectorVersionKey) ?? ""
            guard version != stored else {
                print("[ModelManager] Detector already at version \(version)")
                return
            }

            print("[ModelManager] Downloading detector model v\(version)…")
            // Zip root is BirdDetector.mlmodel (a single file, not a package directory).
            let (zipTemp, _) = try await URLSession.shared.download(from: downloadURL)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: detectorModelURL)
            try FileManager.default.unzipItem(at: zipTemp, to: docs)

            UserDefaults.standard.set(version, forKey: detectorVersionKey)
            cachedDetectorModel = nil
            cachedDetectorModelVersion = nil
            await BirdDetector.shared.invalidateCache()
            print("[ModelManager] Detector updated to v\(version)")
        } catch {
            print("[ModelManager] Detector update check failed: \(error)")
        }
    }
}
