import TensorFlowLite
#if canImport(UIKit)
import UIKit
#endif

struct ClassificationResult {
    let species: String
    let confidence: Float
}

private extension UIImage {
    /// Aspect-fill crop to a square, then resize to `side`×`side` — mirrors
    /// the old Vision-based pipeline's `imageCropAndScaleOption = .centerCrop`,
    /// which TFLite has no built-in equivalent of. Uses UIGraphicsImageRenderer
    /// specifically (not a raw CGContext draw) because it bakes in
    /// `imageOrientation` correctly; a plain CGImage draw ignores it, which
    /// would silently rotate photos taken in portrait.
    func squareCropped(to side: CGFloat) -> UIImage {
        let shortSide = min(size.width, size.height)
        guard shortSide > 0 else { return self }
        let scale = side / shortSide
        let scaledSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            let origin = CGPoint(x: (side - scaledSize.width) / 2, y: (side - scaledSize.height) / 2)
            draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }

    /// Normalized RGB Float32 buffer (no alpha), row-major HWC — matches
    /// convert_photo_model.py's conversion input exactly (scale=1/255,
    /// straight RGB, no channel reordering or mean subtraction).
    func normalizedRGBData(side: Int) -> Data? {
        guard let cgImage = squareCropped(to: CGFloat(side)).cgImage else { return nil }
        var pixelData = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixelData, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var floats = [Float32](repeating: 0, count: side * side * 3)
        for i in 0..<(side * side) {
            floats[i * 3 + 0] = Float32(pixelData[i * 4 + 0]) / 255.0
            floats[i * 3 + 1] = Float32(pixelData[i * 4 + 1]) / 255.0
            floats[i * 3 + 2] = Float32(pixelData[i * 4 + 2]) / 255.0
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

private extension Array where Element == Float32 {
    /// Reinterprets a tensor's raw output Data as [Float32] — the standard
    /// pattern for reading TFLite output tensors (see Google's own TFLite
    /// iOS sample apps).
    init?(unsafeData: Data) {
        guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
        self = unsafeData.withUnsafeBytes { Array($0.bindMemory(to: Element.self)) }
    }
}

/// Runs the bundled/downloaded bird classifier via TensorFlowLiteSwift, not
/// CoreML/Vision — see ml_pipeline/convert_photo_model.py's docstring for
/// why: CoreML conversion of this specific model is broken (confirmed live —
/// a converted .mlpackage produces the same near-uniform, input-independent
/// output for a black image, a white image, random noise, and any real
/// photo), while TFLite conversion of the identical SavedModel produces
/// correct, confident results matching raw TensorFlow inference.
///
/// Actor-isolated deliberately with no manual dispatch to another queue —
/// TFLite's Interpreter.invoke() is not safe to call concurrently on the
/// same instance, and running everything on the actor's own serial executor
/// gets that guarantee for free instead of needing a lock.
actor BirdClassifier {
    static let shared = BirdClassifier()

    /// The model's dedicated "not a bird" background class (see
    /// convert_photo_model.py's BACKGROUND_LABEL) — excluded from results
    /// alongside the confidence floor below, since the model can still be
    /// confidently wrong on an out-of-distribution image rather than
    /// correctly landing on this class.
    private static let unknownLabel = "Unknown / Not a Bird"
    private static let minConfidence: Float32 = 0.5
    private static let inputSide = 224

    private var cachedModelPath: String?
    private var cachedInterpreter: Interpreter?
    private var cachedLabels: [String]?

    private func currentInterpreter() -> (Interpreter, [String])? {
        guard let model = ModelManager.shared.currentClassifierModel else { return nil }
        if let cached = cachedInterpreter, cachedModelPath == model.modelPath, let labels = cachedLabels {
            return (cached, labels)
        }
        do {
            var options = Interpreter.Options()
            options.threadCount = 2
            let interpreter = try Interpreter(modelPath: model.modelPath, options: options)
            try interpreter.allocateTensors()
            cachedInterpreter = interpreter
            cachedModelPath = model.modelPath
            cachedLabels = model.labels
            return (interpreter, model.labels)
        } catch {
            print("[BirdClassifier] Failed to load interpreter: \(error)")
            return nil
        }
    }

    /// Returns the top-`count` predictions, sorted by confidence descending.
    func classifyTopN(image: UIImage, count: Int = 3) async -> [ClassificationResult] {
        guard let (interpreter, labels) = currentInterpreter(),
              let inputData = image.normalizedRGBData(side: Self.inputSide) else { return [] }

        do {
            try interpreter.copy(inputData, toInputAt: 0)
            try interpreter.invoke()
            let output = try interpreter.output(at: 0)
            guard let scores = [Float32](unsafeData: output.data) else { return [] }

            let ranked = scores.enumerated()
                .filter { offset, score in
                    offset < labels.count && labels[offset] != Self.unknownLabel && score >= Self.minConfidence
                }
                .sorted { $0.element > $1.element }
                .prefix(count)
                .map { ClassificationResult(species: labels[$0.offset], confidence: $0.element) }
            return Array(ranked)
        } catch {
            print("[BirdClassifier] Inference failed: \(error)")
            return []
        }
    }

    func classify(image: UIImage) async -> ClassificationResult? {
        await classifyTopN(image: image, count: 1).first
    }

    func invalidateCache() {
        cachedInterpreter = nil
        cachedModelPath = nil
        cachedLabels = nil
    }
}
