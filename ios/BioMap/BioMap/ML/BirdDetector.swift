import Vision
import CoreML
#if canImport(UIKit)
import UIKit
#endif

/// Tier 2 multi-bird photo detection: a real object detector (YOLOv3-Tiny,
/// COCO-trained, Apple's own pre-converted CoreML pipeline — see
/// ml_pipeline/convert_bird_detector_model.py for provenance and why it's
/// not a from-scratch TF->CoreML conversion). The model's pipeline already
/// includes non-max-suppression, so Vision hands back finished
/// VNRecognizedObjectObservation boxes — no anchor-decoding or NMS code of
/// our own needed.
///
/// This only answers "where are the birds" (COCO has one generic "bird"
/// class); MultiBirdDetector.swift crops each region and classifies it with
/// the existing species model to answer "which bird". Optional: the app
/// works fine without this model ever being published (see
/// MultiBirdDetector's saliency fallback) — ModelManager simply never finds
/// an active `photo_detector` version and isDetectorModelAvailable stays false.
actor BirdDetector {
    static let shared = BirdDetector()

    private static let birdLabel = "bird"
    /// A region's "this is a bird" confidence needs to clear this bar before
    /// it's worth cropping + classifying — YOLOv3-Tiny trades precision for
    /// speed, so this filters out its weaker guesses.
    private static let detectionConfidenceThreshold: Float = 0.3

    private var cachedModelVersion: String?
    private var cachedVNModel: VNCoreMLModel?

    private var vnModel: VNCoreMLModel? {
        get throws {
            let version = UserDefaults.standard.string(forKey: "model_detector_version") ?? ""
            if let cached = cachedVNModel, cachedModelVersion == version {
                return cached
            }
            guard let mlModel = ModelManager.shared.currentDetectorModel else { return nil }
            let vn = try VNCoreMLModel(for: mlModel)
            cachedVNModel = vn
            cachedModelVersion = version
            return vn
        }
    }

    /// Returns every detected bird region, sorted by confidence descending.
    /// `boundingBox` is Vision's normalized, bottom-left-origin format,
    /// relative to `image` as given — pass an already orientation-`.up`
    /// image (see MultiBirdDetector.normalizedUp) so callers can crop
    /// consistently without re-deriving orientation math.
    func detectBirds(in image: UIImage) async -> [(boundingBox: CGRect, confidence: Float)] {
        guard let cgImage = image.cgImage, let model = try? vnModel else { return [] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNCoreMLRequest(model: model) { req, _ in
                    let observations = (req.results as? [VNRecognizedObjectObservation]) ?? []
                    let birds: [(CGRect, Float)] = observations.compactMap { obs in
                        guard let top = obs.labels.first,
                              top.identifier == Self.birdLabel,
                              top.confidence >= Self.detectionConfidenceThreshold else { return nil }
                        return (obs.boundingBox, top.confidence)
                    }
                    continuation.resume(returning: birds.sorted { $0.1 > $1.1 })
                }
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    print("[BirdDetector] Inference failed: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func invalidateCache() {
        cachedVNModel = nil
        cachedModelVersion = nil
    }
}
