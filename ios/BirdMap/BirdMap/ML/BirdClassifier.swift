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

    /// The bundled AIY Birds V1 classifier (Google, MobileNetV2 on
    /// iNaturalist 2017 — see ml_pipeline/convert_photo_model.py) has a
    /// dedicated background class for exactly this, given a friendly name
    /// at conversion time. Still, being a plain softmax over 965 classes, it
    /// can be confidently wrong on an out-of-distribution image rather than
    /// correctly landing on this class — the confidence floor below catches
    /// that case too, rather than only trusting the label name.
    private static let unknownLabel = "Unknown / Not a Bird"
    private static let minConfidence: Float = 0.5

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

    /// Returns the top-`count` predictions, sorted by confidence descending.
    func classifyTopN(image: UIImage, count: Int = 3) async -> [ClassificationResult] {
        guard let cgImage = image.cgImage,
              let model = try? vnModel else { return [] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNCoreMLRequest(model: model) { req, _ in
                    let observations = (req.results as? [VNClassificationObservation]) ?? []
                    let top = observations
                        .filter { $0.identifier != Self.unknownLabel && $0.confidence >= Self.minConfidence }
                        .prefix(count)
                        .map { ClassificationResult(species: $0.identifier, confidence: $0.confidence) }
                    continuation.resume(returning: Array(top))
                }
                request.imageCropAndScaleOption = .centerCrop
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    print("[BirdClassifier] Inference failed: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func classify(image: UIImage) async -> ClassificationResult? {
        await classifyTopN(image: image, count: 1).first
    }

    func invalidateCache() {
        cachedVNModel = nil
        cachedModelVersion = nil
    }
}
