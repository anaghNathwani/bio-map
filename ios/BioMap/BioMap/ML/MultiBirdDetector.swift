import Vision
import CoreML
#if canImport(UIKit)
import UIKit
#endif

/// Finds the other birds in a frame. There is no bird detector to lean on (the optional Tier 2 model, BirdDetector.swift, has
/// never been published), so this works from the species classifier alone: it slides overlapping square windows across the
/// frame (a few big ones, and a grid of smaller ones), classifies each window with BirdClassifier, and combines the results.
/// Vision's saliency boxes, and the Tier 2 detector's boxes when that model exists, are added as extra windows.
///
/// Why windows: the classifier looks at one centre-cropped square, so in a frame with two birds side by side the
/// whole-image answer sees half of each and is usually unsure, and the old saliency-only step returned at most a single blob.
/// Measured on 320 composed frames (ml_pipeline/multibird_eval), the old step found a second bird in 0 of 160 multi-bird frames.
enum MultiBirdDetector {
    /// One window's answer: the species the classifier gave for that part of the frame.
    struct RegionHit {
        let species: String
        let confidence: Float
        /// The window, normalised to the frame, origin top-left.
        let box: CGRect
        let source: Source
        let crop: UIImage
        enum Source: String { case tile, salient, detector }
    }

    /// A species other than the primary one is reported when its best window is at least this sure ...
    static let extraConfidence: Float = 0.7
    /// ... or when two or more different windows agree on it and its best is at least this sure.
    static let extraConfidenceWhenCorroborated: Float = 0.6
    static let maxReported = 3
    /// Measured on 320 composite frames: 0.7 halves false extras on single-bird photos for ~3 points of recall.
    static let maxOverlapWithPrimary: CGFloat = 0.7
    /// Saliency boxes whose boxes overlap more than this are one subject (saliency often returns several boxes per subject).
    static let iouDedupeThreshold: CGFloat = 0.3
    /// The big windows slide by half their width; the small ones are this fraction of the short side.
    static let smallWindowFraction: CGFloat = 0.62

    /// Additional distinct species beyond `primarySpecies` (the whole-image answer).
    static func detectAdditional(in rawImage: UIImage, primarySpecies: String?) async -> [BirdCandidate] {
        selectAdditional(from: await scan(rawImage), primarySpecies: primarySpecies)
    }

    /// Classifies every window and returns every answer the classifier was sure enough to give (its own 0.5 floor applies).
    static func scan(_ rawImage: UIImage) async -> [RegionHit] {
        let image = normalizedUp(rawImage)
        guard let cgImage = image.cgImage else { return [] }
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)

        var regions: [(CGRect, RegionHit.Source)] = windows(width: w, height: h).map { ($0, .tile) }
        if ModelManager.shared.isDetectorModelAvailable {
            for r in await BirdDetector.shared.detectBirds(in: image) {
                regions.append((pixelRect(fromVisionBox: r.boundingBox, width: w, height: h, padding: 0.12), .detector))
            }
        } else {
            for box in await salientBoxes(cgImage: cgImage) {
                regions.append((pixelRect(fromVisionBox: box, width: w, height: h, padding: 0.12), .salient))
            }
        }

        var hits: [RegionHit] = []
        for (rect, source) in regions {
            let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
            guard r.width >= 32, r.height >= 32, let cropped = cgImage.cropping(to: r) else { continue }
            let crop = UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
            guard let result = await BirdClassifier.shared.classify(image: crop) else { continue }
            hits.append(RegionHit(species: result.species, confidence: result.confidence,
                                  box: CGRect(x: r.minX / w, y: r.minY / h, width: r.width / w, height: r.height / h),
                                  source: source, crop: crop))
        }
        return hits
    }

    /// Reduces the window answers to the extra species worth showing: one entry per species (its best window), excluding the
    /// primary, and only when the evidence is strong (see the thresholds above).
    static func selectAdditional(from hits: [RegionHit], primarySpecies: String?) -> [BirdCandidate] {
        var best: [String: RegionHit] = [:]
        var windowsAgreeing: [String: Int] = [:]
        for hit in hits {
            windowsAgreeing[hit.species, default: 0] += 1
            if best[hit.species].map({ $0.confidence < hit.confidence }) ?? true { best[hit.species] = hit }
        }
        let primaryBox = primarySpecies.flatMap { best[$0]?.box }
        return best.values
            .filter { $0.species != primarySpecies }
            // A window mostly inside the region the primary species already explains is usually the same bird seen with
            // a different label, not a second bird.
            .filter { hit in primaryBox.map { fractionInside(hit.box, of: $0) <= maxOverlapWithPrimary } ?? true }
            .filter { hit in
                hit.confidence >= extraConfidence
                    || (windowsAgreeing[hit.species, default: 0] >= 2 && hit.confidence >= extraConfidenceWhenCorroborated)
            }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxReported)
            .map { BirdCandidate(species: $0.species, confidence: Double($0.confidence), croppedImage: $0.crop) }
    }

    /// Share of `a`'s area that lies inside `b`.
    static func fractionInside(_ a: CGRect, of b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, a.width * a.height > 0 else { return 0 }
        return i.width * i.height / (a.width * a.height)
    }

    // MARK: - Windows

    /// Pixel windows (top-left origin): squares of the full short side stepping half a window along the long axis, plus a grid
    /// of smaller squares over the whole frame, so a bird near an edge or beside another bird sits mostly inside some window.
    static func windows(width w: CGFloat, height h: CGFloat) -> [CGRect] {
        let short = min(w, h)
        var rects: [CGRect] = []
        for p in positions(length: max(w, h), window: short, stride: short * 0.5) {
            rects.append(w >= h ? CGRect(x: p, y: 0, width: short, height: short) : CGRect(x: 0, y: p, width: short, height: short))
        }
        let small = short * smallWindowFraction
        for px in positions(length: w, window: small, stride: small * 0.5) {
            for py in positions(length: h, window: small, stride: small * 0.5) {
                rects.append(CGRect(x: px, y: py, width: small, height: small))
            }
        }
        return rects
    }

    /// Window start positions covering `length` evenly, first at 0, last flush with the far edge.
    private static func positions(length: CGFloat, window: CGFloat, stride: CGFloat) -> [CGFloat] {
        guard length > window + 1 else { return [0] }
        let n = Int(ceil((length - window) / stride)) + 1
        return (0..<n).map { CGFloat($0) * (length - window) / CGFloat(n - 1) }
    }

    /// Vision's normalised bottom-left-origin box -> a padded pixel rect with a top-left origin.
    private static func pixelRect(fromVisionBox box: CGRect, width w: CGFloat, height h: CGFloat, padding: CGFloat) -> CGRect {
        let rect = CGRect(x: box.minX * w, y: (1 - box.minY - box.height) * h, width: box.width * w, height: box.height * h)
        return rect.insetBy(dx: -rect.width * padding, dy: -rect.height * padding)
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
}
