import Vision
import CoreML
#if canImport(UIKit)
import UIKit
#endif

/// Tier 1 multi-bird photo detection: native Vision saliency, no extra model
/// to ship or convert. Finds visually salient regions in a photo
/// (VNGenerateObjectnessBasedSaliencyImageRequest), crops each, and
/// classifies the crop with the existing on-device BirdClassifier.
///
/// This is not a real object detector — it has no concept of "bird" versus
/// any other salient thing in frame, it just finds regions that stand out
/// visually. Results are filtered hard by classifier confidence and
/// deduplicated against the primary whole-image classification so a single
/// bird photographed at a flattering angle doesn't get double-counted as
/// two birds. Superseded by a real object-detection model (Tier 2) once
/// that ships — see BirdDetector.swift — which is preferred whenever its
/// model is available locally, with this saliency path as the fallback.
enum MultiBirdDetector {
    /// A secondary crop's classification needs to clear this bar to be worth
    /// surfacing as "we also saw X" — mirrors live_poll.py's audio threshold.
    /// Saliency + classification stacks two error-prone steps on top of each
    /// other, so the bar is intentionally high to avoid false "multiple
    /// birds" claims from e.g. a salient patch of foliage.
    static let secondaryConfidenceThreshold: Float = 0.6
    static let maxRegions = 4
    static let maxReported = 3
    /// Regions whose boxes overlap more than this are treated as the same
    /// salient object — saliency often returns several overlapping boxes
    /// for one subject rather than one box per distinct subject.
    static let iouDedupeThreshold: CGFloat = 0.3

    /// Returns additional distinct-species candidates beyond `primarySpecies`
    /// (the existing whole-image classification). Prefers the real object
    /// detector (Tier 2, BirdDetector.swift) whenever its model has been
    /// published and downloaded; falls back to Vision saliency (Tier 1) when
    /// it hasn't — see ModelManager.isDetectorModelAvailable.
    static func detectAdditional(in rawImage: UIImage, primarySpecies: String?) async -> [BirdCandidate] {
        let image = normalizedUp(rawImage)
        guard let cgImage = image.cgImage else { return [] }

        if ModelManager.shared.isDetectorModelAvailable {
            let regions = await BirdDetector.shared.detectBirds(in: image)
            // A real detector confidently reporting zero regions is more
            // trustworthy than falling back to saliency's guesswork, so
            // don't fall through here even if regions is empty.
            return await classify(boxes: regions.map { $0.boundingBox }, in: image, primarySpecies: primarySpecies)
        }

        let boxes = await salientBoxes(cgImage: cgImage)
        guard boxes.count > 1 else { return [] }
        return await classify(boxes: boxes, in: image, primarySpecies: primarySpecies)
    }

    /// Crops each box, classifies the crop's species, and dedupes down to
    /// the best-confidence match per distinct species (excluding
    /// `primarySpecies`, already shown as the primary result elsewhere).
    private static func classify(boxes: [CGRect], in image: UIImage, primarySpecies: String?) async -> [BirdCandidate] {
        var bestPerSpecies: [String: BirdCandidate] = [:]
        for box in boxes.prefix(maxRegions) {
            guard let cropped = crop(image: image, normalizedBox: box) else { continue }
            guard let result = await BirdClassifier.shared.classify(image: cropped) else { continue }
            guard result.confidence >= secondaryConfidenceThreshold else { continue }
            if let primarySpecies, result.species == primarySpecies { continue }
            if let existing = bestPerSpecies[result.species], existing.confidence >= Double(result.confidence) {
                continue
            }
            bestPerSpecies[result.species] = BirdCandidate(
                species: result.species,
                confidence: Double(result.confidence),
                croppedImage: cropped
            )
        }
        return Array(bestPerSpecies.values.sorted { $0.confidence > $1.confidence }.prefix(maxReported))
    }

    private static func salientBoxes(cgImage: CGImage) async -> [CGRect] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGenerateObjectnessBasedSaliencyImageRequest()
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                    guard let result = request.results?.first,
                          let salientObjects = result.salientObjects else {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(returning: dedupe(salientObjects.map { $0.boundingBox }))
                } catch {
                    print("[MultiBirdDetector] Saliency request failed: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private static func dedupe(_ boxes: [CGRect]) -> [CGRect] {
        var kept: [CGRect] = []
        for box in boxes {
            if kept.contains(where: { iou($0, box) > iouDedupeThreshold }) { continue }
            kept.append(box)
        }
        return kept
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    /// Redraws the image so its orientation is always `.up` before any
    /// Vision work or cropping happens — camera captures commonly carry a
    /// non-`.up` `imageOrientation` while the backing `CGImage` buffer stays
    /// unrotated, which would otherwise silently misalign Vision's
    /// bottom-left-origin bounding boxes against a naively-cropped buffer.
    private static func normalizedUp(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    /// `normalizedBox` is Vision's normalized, bottom-left-origin format.
    /// `image` must already be orientation-`.up` (see `normalizedUp`).
    private static func crop(image: UIImage, normalizedBox box: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let pixelW = CGFloat(cgImage.width)
        let pixelH = CGFloat(cgImage.height)
        let x = box.minX * pixelW
        let width = box.width * pixelW
        let height = box.height * pixelH
        let y = (1 - box.minY - box.height) * pixelH // bottom-left -> top-left origin
        let rect = CGRect(x: x, y: y, width: width, height: height)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        guard rect.width > 0, rect.height > 0, let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }
}
