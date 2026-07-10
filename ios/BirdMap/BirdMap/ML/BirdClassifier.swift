import CoreML
import Vision
#if canImport(UIKit)
import UIKit
#endif

struct ClassificationResult {
    let species: String
    let confidence: Float
}

// Actor serializes all cache reads/writes, eliminating the data race on
// cachedVNModel that would occur when classify() is called concurrently.
actor BirdClassifier {
    static let shared = BirdClassifier()

    private var cachedModelVersion: String?
    private var cachedVNModel: VNCoreMLModel?

    private var vnModel: VNCoreMLModel? {
        get throws {
            let version = UserDefaults.standard.string(forKey: "model_version") ?? ""
            if let cached = cachedVNModel, cachedModelVersion == version {
                return cached
            }
            guard let mlModel = ModelManager.shared.currentModel else { return nil }
            let vn = try VNCoreMLModel(for: mlModel)
            cachedVNModel = vn
            cachedModelVersion = version
            return vn
        }
    }

    func classify(image: UIImage) async -> ClassificationResult? {
        guard let cgImage = image.cgImage,
              let model = try? vnModel else { return nil }

        return await withCheckedContinuation { continuation in
            // Dispatch off the actor's executor onto a background thread for
            // CPU-heavy Vision inference, then resume the continuation.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNCoreMLRequest(model: model) { req, _ in
                    let top = (req.results as? [VNClassificationObservation])?.first
                    continuation.resume(returning: top.map {
                        ClassificationResult(species: $0.identifier, confidence: $0.confidence)
                    })
                }
                request.imageCropAndScaleOption = .centerCrop
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    print("[BirdClassifier] Inference failed: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func invalidateCache() {
        cachedVNModel = nil
        cachedModelVersion = nil
    }
}
