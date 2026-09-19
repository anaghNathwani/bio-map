import AVFoundation
import TensorFlowLite

/// On-device bird-call ID using Cornell's BirdNET V2.4 (the same open-weight
/// model ml_pipeline/live_poll.py runs server-side via birdnetlib, bundled as
/// ML/Bundled/BundledBirdNET.tflite), so a recording gets an answer the moment
/// it's submitted instead of waiting for the scheduled GitHub Actions job.
///
/// Pipeline (verified in Python against birdnetlib on a real American Robin
/// recording before being ported here): decode to 48 kHz mono Float32, cut
/// into 3-second windows, feed each raw waveform (no spectrogram — the model
/// computes that itself) as a [1, 144000] tensor, apply a sigmoid to the 6522
/// output logits, keep each species' best score across windows.
///
/// Actor-isolated with no manual queue hopping: TFLite's Interpreter.invoke()
/// isn't safe to call concurrently on one instance.
actor BirdNETClassifier {
    static let shared = BirdNETClassifier()

    private static let sampleRate = 48_000.0
    private static let windowSamples = 144_000          // 3 s at 48 kHz
    private static let minTailSamples = 48_000          // pad a final partial window only if >= 1 s
    /// Deliberately stricter than the server's 0.1 — at 0.1 BirdNET is happy to
    /// name a plausible-sounding bird for noise, which is exactly the
    /// hallucination behaviour we don't want to ship. With a GPS fix the
    /// location filter below removes most of that, so the bar can be lower;
    /// without one there's nothing else guarding against it, so it's higher.
    private static let minConfidenceWithLocation: Float = 0.25
    private static let minConfidenceWithoutLocation: Float = 0.35
    private static let topPerWindow = 5
    /// BirdNET's own default for "occurs here at this time of year".
    private static let locationFilterThreshold: Float32 = 0.03

    private var interpreter: Interpreter?
    private var labels: [String]?
    private var locationModel: Interpreter?

    enum ClassifierError: Error { case modelMissing, audioUnreadable, unexpectedOutput }

    private func loadIfNeeded() throws -> (Interpreter, [String]) {
        if let interpreter, let labels { return (interpreter, labels) }
        guard let modelURL = Bundle.main.url(forResource: "BundledBirdNET", withExtension: "tflite"),
              let labelsURL = Bundle.main.url(forResource: "BundledBirdNETLabels", withExtension: "json"),
              let labelsData = try? Data(contentsOf: labelsURL),
              let labels = try? JSONDecoder().decode([String].self, from: labelsData)
        else { throw ClassifierError.modelMissing }

        var options = Interpreter.Options()
        options.threadCount = 2
        let interpreter = try Interpreter(modelPath: modelURL.path, options: options)
        try interpreter.allocateTensors()
        self.interpreter = interpreter
        self.labels = labels
        return (interpreter, labels)
    }

    /// BirdNET's location/season meta-model: which species plausibly occur at
    /// this spot in this week of the year. Without this, BirdNET will happily
    /// report e.g. a European woodpecker for steady noise recorded in
    /// California (confirmed on a white-noise control clip).
    private func speciesIndices(near latitude: Double, _ longitude: Double, on date: Date) throws -> Set<Int> {
        if locationModel == nil {
            guard let url = Bundle.main.url(forResource: "BundledBirdNETLocation", withExtension: "tflite") else {
                throw ClassifierError.modelMissing
            }
            let model = try Interpreter(modelPath: url.path)
            try model.allocateTensors()
            locationModel = model
        }
        guard let model = locationModel else { throw ClassifierError.modelMissing }

        let calendar = Calendar(identifier: .gregorian)
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let daysInYear = Double(calendar.range(of: .day, in: .year, for: date)?.count ?? 365)
        let week48 = Float32(min(48, max(1, (dayOfYear / daysInYear * 48).rounded(.up))))

        let input: [Float32] = [Float32(latitude), Float32(longitude), week48]
        try model.copy(input.withUnsafeBufferPointer { Data(buffer: $0) }, toInputAt: 0)
        try model.invoke()
        let data = try model.output(at: 0).data
        guard data.count % MemoryLayout<Float32>.stride == 0 else { throw ClassifierError.unexpectedOutput }
        let probabilities = data.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) }
        return Set(probabilities.indices.filter { probabilities[$0] >= Self.locationFilterThreshold })
    }

    /// Returns the species heard, best first, each with its highest confidence
    /// across the recording — empty if nothing cleared the confidence bar.
    /// Pass the recording's GPS position when there is a real fix (not a
    /// made-up default): it restricts results to species that occur there.
    /// Throws (rather than returning empty) when analysis itself couldn't run,
    /// so callers can tell "no bird heard" apart from "couldn't analyze".
    func classify(
        fileURL: URL,
        latitude: Double? = nil,
        longitude: Double? = nil,
        date: Date = Date(),
        maxResults: Int = 4
    ) throws -> [ClassificationResult] {
        let (interpreter, labels) = try loadIfNeeded()
        let samples = try Self.loadSamples(from: fileURL)

        var allowed: Set<Int>?
        if let latitude, let longitude {
            allowed = try? speciesIndices(near: latitude, longitude, on: date)
        }
        let minConfidence = allowed != nil ? Self.minConfidenceWithLocation : Self.minConfidenceWithoutLocation

        var best: [String: Float] = [:]
        var start = 0
        while start < samples.count {
            var window = Array(samples[start..<min(start + Self.windowSamples, samples.count)])
            start += Self.windowSamples
            if window.count < Self.windowSamples {
                guard window.count >= Self.minTailSamples else { break }
                window += [Float](repeating: 0, count: Self.windowSamples - window.count)
            }

            try interpreter.copy(window.withUnsafeBufferPointer { Data(buffer: $0) }, toInputAt: 0)
            try interpreter.invoke()
            let output = try interpreter.output(at: 0).data
            guard output.count % MemoryLayout<Float32>.stride == 0 else { throw ClassifierError.unexpectedOutput }
            let logits = output.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) }
            guard logits.count == labels.count else { throw ClassifierError.unexpectedOutput }

            // Non-bird classes (human voice, dog, engine, noise, crickets...) have
            // blank labels — drop them *before* ranking so a loud one can't crowd
            // a real bird out of the top few.
            let top = logits.enumerated()
                .filter { !labels[$0.offset].isEmpty && (allowed?.contains($0.offset) ?? true) }
                .sorted { $0.element > $1.element }
                .prefix(Self.topPerWindow)
            for (index, logit) in top {
                let name = labels[index]
                let score = 1 / (1 + exp(-max(-15, min(15, logit))))
                if score >= minConfidence { best[name] = max(best[name] ?? 0, score) }
            }
        }

        return best
            .sorted { $0.value > $1.value }
            .prefix(maxResults)
            .map { ClassificationResult(species: $0.key, confidence: $0.value) }
    }

    /// Decodes any file AVFoundation can read (the app records AAC .m4a) to
    /// 48 kHz mono Float32 samples.
    private static func loadSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw ClassifierError.audioUnreadable }
        try file.read(into: input)

        let ratio = sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw ClassifierError.audioUnreadable
        }

        var supplied = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let conversionError { throw conversionError }
        guard let channel = output.floatChannelData?[0], output.frameLength > 0 else {
            throw ClassifierError.audioUnreadable
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
