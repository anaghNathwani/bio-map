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
    /// / `convert_bird_detector_model.py` + `publish_model.py` primarily
    /// through Firestore — no Storage, no third-party host needed for the
    /// primary path. A model is too big for one 1 MiB Firestore document, so
    /// it's split into base64 chunk documents under
    /// `model_versions/{id}/chunks`, reassembled here — see
    /// docs/ML_PIPELINE.md. If the Firestore chunks can't be assembled for
    /// any reason, falls back to downloading the same zip from the doc's
    /// `fallbackURL` (a Supabase Storage public URL), when present.
    func checkForUpdate() async {
        await checkForClassifierUpdate()
        await checkForDetectorUpdate()
    }

    /// Fetches every chunk doc (ordered by `index`) under a model_versions
    /// doc and concatenates the *decoded* bytes — decoding each chunk on its
    /// own rather than concatenating the base64 strings first, since a chunk
    /// boundary chosen by raw byte count won't generally land on a 3-byte
    /// base64 group boundary, so an intermediate chunk's base64 can carry
    /// padding that would corrupt a naive string-level concatenation.
    private func assembleModelData(from versionDoc: QueryDocumentSnapshot) async throws -> Data {
        let chunksSnap = try await versionDoc.reference.collection("chunks")
            .order(by: "index")
            .getDocuments()
        guard !chunksSnap.documents.isEmpty else {
            throw NSError(domain: "ModelManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No chunk documents found"
            ])
        }
        var result = Data()
        for chunkDoc in chunksSnap.documents {
            guard let base64 = chunkDoc.data()["data"] as? String,
                  let chunkData = Data(base64Encoded: base64) else {
                throw NSError(domain: "ModelManager", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Malformed chunk \(chunkDoc.documentID)"
                ])
            }
            result.append(chunkData)
        }
        return result
    }

    /// Firestore primary failed (missing/malformed chunks, read error, etc.)
    /// — try the Supabase fallback URL stored on the same doc, if published.
    private func fetchModelData(from doc: QueryDocumentSnapshot) async throws -> Data {
        do {
            return try await assembleModelData(from: doc)
        } catch {
            guard let fallbackURLString = doc.data()["fallbackURL"] as? String,
                  let fallbackURL = URL(string: fallbackURLString) else {
                throw error
            }
            print("[ModelManager] Firestore chunks unavailable (\(error)), trying fallback URL…")
            let (data, _) = try await URLSession.shared.data(from: fallbackURL)
            return data
        }
    }

    private func checkForClassifierUpdate() async {
        do {
            let snap = try await Firestore.firestore().collection("model_versions")
                .whereField("mediaType", isEqualTo: "photo")
                .whereField("isActive", isEqualTo: true)
                .limit(to: 1)
                .getDocuments()
            guard let doc = snap.documents.first,
                  let version = doc.data()["version"] as? String else {
                print("[ModelManager] No active photo model published yet")
                return
            }

            let stored = UserDefaults.standard.string(forKey: versionKey) ?? ""
            guard version != stored else {
                print("[ModelManager] Classifier already at version \(version)")
                return
            }

            print("[ModelManager] Downloading classifier model v\(version)…")
            let zipData = try await assembleModelData(from: doc)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let zipTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
            try zipData.write(to: zipTemp)
            try? FileManager.default.removeItem(at: modelURL)
            try FileManager.default.unzipItem(at: zipTemp, to: docs)
            try? FileManager.default.removeItem(at: zipTemp)

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
                  let version = doc.data()["version"] as? String else {
                print("[ModelManager] No active photo detector model published yet")
                return
            }

            let stored = UserDefaults.standard.string(forKey: detectorVersionKey) ?? ""
            guard version != stored else {
                print("[ModelManager] Detector already at version \(version)")
                return
            }

            print("[ModelManager] Downloading detector model v\(version)…")
            let zipData = try await assembleModelData(from: doc)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let zipTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
            try zipData.write(to: zipTemp)
            try? FileManager.default.removeItem(at: detectorModelURL)
            try FileManager.default.unzipItem(at: zipTemp, to: docs)
            try? FileManager.default.removeItem(at: zipTemp)

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
