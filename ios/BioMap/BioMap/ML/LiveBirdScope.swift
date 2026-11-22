import AVFoundation
import Vision
import CoreImage
import UIKit

/// One bird the live scope is following.
struct LiveBird: Identifiable, Equatable {
    let id: Int
    /// Normalised (0...1) in the camera frame, top-left origin.
    var box: CGRect
    /// Best guess so far; nil until the species model has had a look.
    var species: String?
    var confidence: Float = 0
}

/// Incognito live view: runs the camera, finds birds in each frame, names them, and keeps nothing.
/// Frames are looked at and dropped. There is no recording output, no audio input, no photo output, no saving and no
/// network use anywhere in this class.
///
/// Where the birds are comes from the bundled YOLOv3-Tiny (COCO "bird") detector, the same model the photo flow uses;
/// which species comes from the same on-device classifier as photos, run on a crop of each followed bird about once a
/// second, with the answers voted over time so the label doesn't flicker.
final class LiveBirdScope: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var birds: [LiveBird] = []
    @Published private(set) var status: Status = .starting
    @Published var selectedID: Int?

    enum Status: Equatable { case starting, running, denied, unavailable }

    let session = AVCaptureSession()
    /// Frame size as delivered (portrait), for mapping boxes onto the preview.
    @Published private(set) var frameSize = CGSize(width: 720, height: 1280)

    // Everything below is touched only on `work`.
    private let work = DispatchQueue(label: "biomap.livescope", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private var request: VNCoreMLRequest?
    private let ciContext = CIContext()
    private var lastRun = Date.distantPast
    private var tracks: [Track] = []
    private var nextID = 1

    private struct Track {
        var bird: LiveBird
        var misses = 0
        var votes: [String: Float] = [:]
        var lastClassified = Date.distantPast
        var classifying = false
    }

    static let detectEvery: TimeInterval = 0.2          // ~5 detections a second
    static let classifyEvery: TimeInterval = 1.0
    static let detectionThreshold: Float = 0.35
    static let maxMisses = 5

    // MARK: - Session

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: work.async { self.run() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                if ok { self.work.async { self.run() } } else { self.set(.denied) }
            }
        default: set(.denied)
        }
    }

    func stop() {
        work.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.tracks.removeAll()
            DispatchQueue.main.async { self.birds = []; self.selectedID = nil }
        }
    }

    private func set(_ s: Status) { DispatchQueue.main.async { self.status = s } }

    private func run() {
        guard configure() else { return }
        if !session.isRunning { session.startRunning() }
        set(.running)
    }

    private func configure() -> Bool {
        if configured { return true }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              let model = Self.loadDetector() else { set(.unavailable); return false }
        let request = VNCoreMLRequest(model: model)
        // Fit the whole frame inside the model's square input (padded, not stretched) and Vision hands the boxes back in
        // frame coordinates. Stretching a tall camera frame into the square found no birds at all in testing.
        request.imageCropAndScaleOption = .scaleFit
        self.request = request

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        if session.canAddInput(input) { session.addInput(input) }
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: work)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90          // upright frames, so boxes need no rotation maths
        }
        configured = true
        return true
    }

    private static func loadDetector() -> VNCoreMLModel? {
        guard let url = Bundle.main.url(forResource: "BundledBirdDetector", withExtension: "mlmodelc"),
              let ml = try? MLModel(contentsOf: url) else { return nil }
        return try? VNCoreMLModel(for: ml)
    }

    // MARK: - Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastRun) >= Self.detectEvery,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer), let request else { return }
        lastRun = now

        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        if size != frameSize { DispatchQueue.main.async { self.frameSize = size } }

        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        let found: [CGRect] = ((request.results as? [VNRecognizedObjectObservation]) ?? []).compactMap { o in
            guard let top = o.labels.first, top.identifier == "bird", top.confidence >= Self.detectionThreshold else { return nil }
            let b = o.boundingBox                         // Vision: bottom-left origin
            return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
        }
        update(with: found, buffer: buffer, now: now)
    }

    /// Matches this frame's boxes to the birds already followed, adds new ones, drops ones gone for a while, and
    /// schedules a species check for any that are due.
    private func update(with boxes: [CGRect], buffer: CVPixelBuffer, now: Date) {
        var unmatched = Array(boxes.indices)
        for i in tracks.indices {
            var best: (idx: Int, iou: CGFloat)?
            for j in unmatched {
                let v = Self.iou(tracks[i].bird.box, boxes[j])
                if v > 0.25, v > (best?.iou ?? 0) { best = (j, v) }
            }
            if let (j, _) = best {
                let old = tracks[i].bird.box, new = boxes[j]
                // Ease toward the new box so the overlay glides instead of jittering.
                tracks[i].bird.box = CGRect(x: old.minX + (new.minX - old.minX) * 0.6, y: old.minY + (new.minY - old.minY) * 0.6,
                                            width: old.width + (new.width - old.width) * 0.6, height: old.height + (new.height - old.height) * 0.6)
                tracks[i].misses = 0
                unmatched.removeAll { $0 == j }
            } else {
                tracks[i].misses += 1
            }
        }
        tracks.removeAll { $0.misses > Self.maxMisses }
        for j in unmatched {
            tracks.append(Track(bird: LiveBird(id: nextID, box: boxes[j], species: nil)))
            nextID += 1
        }

        for i in tracks.indices where tracks[i].misses == 0
            && !tracks[i].classifying && now.timeIntervalSince(tracks[i].lastClassified) >= Self.classifyEvery {
            tracks[i].classifying = true
            tracks[i].lastClassified = now
            if let crop = crop(buffer, box: tracks[i].bird.box) {
                let id = tracks[i].bird.id
                Task.detached(priority: .userInitiated) { [weak self] in
                    let result = await BirdClassifier.shared.classify(image: crop)
                    self?.work.async { self?.apply(result, to: id) }
                }
            } else {
                tracks[i].classifying = false
            }
        }

        let snapshot = tracks.filter { $0.misses <= 1 }.map(\.bird)
        DispatchQueue.main.async {
            self.birds = snapshot
            if let s = self.selectedID, !snapshot.contains(where: { $0.id == s }) { self.selectedID = nil }
        }
    }

    /// Folds one species answer into the bird's running vote; the label is whichever species has the most weight.
    private func apply(_ result: ClassificationResult?, to id: Int) {
        guard let i = tracks.firstIndex(where: { $0.bird.id == id }) else { return }
        tracks[i].classifying = false
        for key in tracks[i].votes.keys { tracks[i].votes[key]! *= 0.8 }       // older answers fade
        if let r = result { tracks[i].votes[r.species, default: 0] += r.confidence }
        if let top = tracks[i].votes.max(by: { $0.value < $1.value }), top.value > 0.3 {
            tracks[i].bird.species = top.key
            tracks[i].bird.confidence = result?.species == top.key ? (result?.confidence ?? tracks[i].bird.confidence) : tracks[i].bird.confidence
        }
    }

    private func crop(_ buffer: CVPixelBuffer, box: CGRect) -> UIImage? {
        let w = CGFloat(CVPixelBufferGetWidth(buffer)), h = CGFloat(CVPixelBufferGetHeight(buffer))
        let padded = box.insetBy(dx: -box.width * 0.12, dy: -box.height * 0.12).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        // CoreImage is bottom-left origin.
        let rect = CGRect(x: padded.minX * w, y: (1 - padded.maxY) * h, width: padded.width * w, height: padded.height * h).integral
        guard rect.width >= 32, rect.height >= 32 else { return nil }
        let image = CIImage(cvPixelBuffer: buffer).cropped(to: rect)
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull else { return 0 }
        let inter = i.width * i.height
        return inter / (a.width * a.height + b.width * b.height - inter)
    }
}
