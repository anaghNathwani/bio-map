import CoreML
import Vision
import UIKit

struct ClassificationResult {
    let species: String
    let confidence: Float
}

final class BirdClassifier {
    static let shared = BirdClassifier()

    func classify(image: UIImage) async -> ClassificationResult? {
        guard let model = ModelManager.shared.currentModel,
              let cgImage = image.cgImage else { return nil }

        do {
            let vnModel = try VNCoreMLModel(for: model)
            return try await withCheckedThrowingContinuation { continuation in
                let request = VNCoreMLRequest(model: vnModel) { req, err in
                    if let err {
                        continuation.resume(throwing: err)
                        return
                    }
                    guard let results = req.results as? [VNClassificationObservation],
                          let top = results.first else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: ClassificationResult(
                        species: top.identifier,
                        confidence: top.confidence
                    ))
                }
                request.imageCropAndScaleOption = .centerCrop
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            return nil
        }
    }
}
