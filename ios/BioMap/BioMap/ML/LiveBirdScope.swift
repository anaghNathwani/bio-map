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

