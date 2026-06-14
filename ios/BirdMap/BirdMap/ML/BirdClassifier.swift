import CoreML
import Vision
#if canImport(UIKit)
import UIKit
#endif

struct ClassificationResult {
    let species: String
    let confidence: Float
}

final class BirdClassifier {
    static let shared = BirdClassifier()

    // Cache both the loaded model and the Vision wrapper — recreating VNCoreMLModel
    // on every inference wastes CPU cycles and increases battery drain.
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

    // Run inference on a dedicated background queue at .userInitiated QoS.
    // Avoids running CPU-heavy work on the main actor which would use higher
    // scheduling priority than needed and hurt battery life.
    private let inferenceQueue = DispatchQueue(
        label: "com.birdmap.inference",
        qos: .userInitiated
    )

    func classify(image: UIImage) async -> ClassificationResult? {
        guard let cgImage = image.cgImage,
              let model = try? vnModel else { return nil }

        return await withCheckedContinuation { continuation in
            inferenceQueue.async {
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
