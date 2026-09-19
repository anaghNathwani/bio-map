import SwiftUI
import AVFoundation
import CoreLocation
import FirebaseFirestore
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AudioRecorderViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isRecording = false
    @Published var isUploading = false
    @Published var uploadSuccess = false
    @Published var error: String?
    @Published var recordingSeconds: Int = 0
    @Published var aiSuggestion: String?
    @Published var aiConfidence: Double?
    /// Additional distinct species BirdNET heard in the same recording, beyond
    /// the primary aiSuggestion — see live_poll.py's aiSpeciesSuggestions.
    @Published var aiAdditionalSuggestions: [BirdCandidate] = []
    @Published var meterLevel: Float = 0
    @Published var notes = ""
    @Published var hasRecording = false
    /// True while waiting for the self-hosted BirdNET watcher (ml_pipeline/live_poll.py)
    /// to analyze the just-uploaded recording.
    @Published var isAnalyzing = false
    @Published var analysisTimedOut = false
    @Published var lastUploadedSightingID: String?
    /// On-device BirdNET ran on the last submission and didn't hear a bird it
    /// was confident about (as opposed to not being able to run at all).
    @Published var noBirdDetected = false

    /// On-device identification of the take currently held (before submitting),
    /// run as soon as recording stops — same idea as photos, which classify the
    /// moment one is picked. nil = not analyzed (still running, or it failed).
    @Published var isIdentifying = false
    /// Converting a picked audio file into a recording (see AudioImporter).
    @Published var isImporting = false
    /// Shown after an import when something the user should know happened (e.g. trimmed).
    @Published var importNotice: String?
    @Published var identification: [ClassificationResult]?
    @Published var identificationError: String?
    /// Whether the last identification could use a real GPS fix to narrow the
    /// species list — surfaced in the UI since it changes how strict we are.
    @Published var identificationUsedLocation = false
    private var identificationTask: Task<Void, Never>?

    /// Recordings are embedded as base64 directly in the Firestore sighting
    /// doc (no Storage/backend — see FirebaseService.uploadAudio), which caps
    /// a document at 1 MiB; 30s of mono AAC leaves generous headroom even at
    /// a generous bitrate, while still being plenty for BirdNET's ~3s windows.
    static let maxRecordingSeconds = 30

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var countTimer: Timer?
    private var sightingListener: ListenerRegistration?
    private(set) var recordingURL: URL?
    private let locationManager = CLLocationManager()
    private(set) var lastLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
    }

    func startLocationUpdates() { locationManager.startUpdatingLocation() }
    func stopLocationUpdates() { locationManager.stopUpdatingLocation() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.lastLocation = loc }
    }

    func startRecording() {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            self.error = "Microphone unavailable: \(error.localizedDescription)"
            return
        }
        #endif

        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("bird_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
            recordingURL = url
            hasRecording = false
            clearIdentification()
            importNotice = nil
            isRecording = true
            recordingSeconds = 0
            error = nil

            countTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.recordingSeconds += 1
                    if self.recordingSeconds >= Self.maxRecordingSeconds { self.stopRecording() }
                }
            }
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.recorder?.updateMeters()
                let power = self?.recorder?.averagePower(forChannel: 0) ?? -80
                let normalized = Float(max(0, min(1, (power + 80) / 80)))
                Task { @MainActor [weak self] in self?.meterLevel = normalized }
            }
        } catch {
            self.error = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        let wasRecording = isRecording
        recorder?.stop()
        meterTimer?.invalidate()
        countTimer?.invalidate()
        isRecording = false
        meterLevel = 0
        hasRecording = recordingURL != nil
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
        if wasRecording && hasRecording { identifyRecording() }
    }

    /// Uses an existing audio file as the take instead of recording one — the
    /// audio equivalent of picking a photo from the library. The file is
    /// converted to the recorder's small mono AAC format and capped at
    /// `maxRecordingSeconds` (see AudioImporter for why), then identified
    /// exactly like a fresh recording.
    func importAudio(from source: URL) async {
        // Files chosen via the system picker are only readable inside this scope.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        isImporting = true
        error = nil
        importNotice = nil
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("bird_import_\(UUID().uuidString).m4a")
        let maxSeconds = Double(Self.maxRecordingSeconds)

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try AudioImporter.convert(source, to: destination, maxSeconds: maxSeconds)
            }.value

            if let old = recordingURL { try? FileManager.default.removeItem(at: old) }
            clearIdentification()
            recordingURL = destination
            recordingSeconds = max(1, Int(result.seconds.rounded()))
            hasRecording = true
            if result.wasTrimmed {
                importNotice = "That file is longer than \(Self.maxRecordingSeconds) seconds, so only the first \(Self.maxRecordingSeconds) were kept."
            }
            identifyRecording()
        } catch {
            self.error = "Couldn't use that file: \(error.localizedDescription)"
        }
        isImporting = false
    }

    /// Runs BirdNET on the current take (see BirdNETClassifier). Only a genuine
    /// GPS fix is passed for the location filter — `upload()` falls back to a
    /// fixed San Francisco default when there isn't one, and narrowing a
    /// recording made elsewhere down to California species would be wrong.
    func identifyRecording() {
        guard let url = recordingURL else { return }
        identificationTask?.cancel()
        identification = nil
        identificationError = nil
        isIdentifying = true
        let latitude = lastLocation?.coordinate.latitude
        let longitude = lastLocation?.coordinate.longitude
        identificationUsedLocation = latitude != nil && longitude != nil

        identificationTask = Task { [weak self] in
            var results: [ClassificationResult]?
            var failure: String?
            do {
                results = try await BirdNETClassifier.shared.classify(fileURL: url, latitude: latitude, longitude: longitude)
            } catch {
                failure = error.localizedDescription
                print("[AudioRecorderViewModel] On-device BirdNET failed: \(error)")
            }
            guard let self, !Task.isCancelled, self.recordingURL == url else { return }
            self.identification = results
            self.identificationError = failure
            self.isIdentifying = false
        }
    }

    private func clearIdentification() {
        identificationTask?.cancel()
        identificationTask = nil
        identification = nil
        identificationError = nil
        isIdentifying = false
    }

    func upload() async {
        guard let url = recordingURL, let data = try? Data(contentsOf: url) else {
            error = "No recording found"; return
        }
        let location = lastLocation ?? CLLocation(latitude: 37.7749, longitude: -122.4194)

        isUploading = true
        error = nil
        noBirdDetected = false
        let sightingID = UUID().uuidString

        // Identification already ran when recording stopped; if it's still going,
        // wait for it. nil means it couldn't run at all — distinct from "ran and
        // heard no bird" — and leaves the sighting to the scheduled server job.
        await identificationTask?.value
        let detections = identification
        let top = detections?.first
        let extras = (detections ?? []).dropFirst().map {
            BirdCandidate(species: $0.species, confidence: Double($0.confidence))
        }

        do {
            let (audioURL, fallbackURL) = try await FirebaseService.shared.uploadAudio(data, sightingID: sightingID, filename: url.lastPathComponent)
            _ = try await FirebaseService.shared.createSighting(
                photoURL: nil,
                thumbnailURL: nil,
                audioURL: audioURL,
                audioFallbackURL: fallbackURL,
                mediaType: "audio",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                notes: notes.isEmpty ? nil : notes,
                aiSpecies: top?.species,
                aiConfidence: top.map { Double($0.confidence) },
                aiAdditionalSpecies: Array(extras),
                aiAnalyzed: detections != nil
            )
            notes = ""
            hasRecording = false
            recordingURL = nil
            recordingSeconds = 0
            clearIdentification()
            lastUploadedSightingID = sightingID
            if let detections {
                aiAdditionalSuggestions = Array(extras)
                aiConfidence = top.map { Double($0.confidence) }
                noBirdDetected = detections.isEmpty
                if let top {
                    aiSuggestion = top.species      // the view's onChange presents the AI review card
                } else {
                    uploadSuccess = true
                }
            } else {
                startAnalyzing(sightingID: sightingID)
            }
        } catch {
            self.error = "Upload failed: \(error.localizedDescription)"
        }
        isUploading = false
    }

    /// Listens for the self-hosted BirdNET watcher (ml_pipeline/live_poll.py) to
    /// populate this sighting's AI suggestion. Falls back to a plain success state
    /// if nothing arrives within the timeout (e.g. the watcher isn't running) —
    /// the sighting is still saved and can be annotated manually later.
    private func startAnalyzing(sightingID: String) {
        isAnalyzing = true
        analysisTimedOut = false
        aiSuggestion = nil
        aiConfidence = nil
        aiAdditionalSuggestions = []

        sightingListener?.remove()
        sightingListener = FirebaseService.shared.db.collection("sightings").document(sightingID)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let data = snapshot?.data(),
                      let species = data["aiSpeciesSuggestion"] as? String else { return }
                Task { @MainActor in
                    guard self.isAnalyzing else { return } // already resolved (e.g. timed out)
                    self.aiSuggestion = species
                    self.aiConfidence = data["aiConfidence"] as? Double
                    if let extra = data["aiSpeciesSuggestions"] as? [[String: Any]] {
                        // Drop the first entry — it's the same bird as aiSuggestion above,
                        // already shown as the primary card; this list is the rest.
                        self.aiAdditionalSuggestions = extra.dropFirst().compactMap { entry in
                            guard let sp = entry["species"] as? String else { return nil }
                            let conf = entry["confidence"] as? Double ?? 0
                            return BirdCandidate(species: sp, confidence: conf)
                        }
                    }
                    self.isAnalyzing = false
                    self.sightingListener?.remove()
                    self.sightingListener = nil
                }
            }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard let self, self.isAnalyzing else { return }
            self.isAnalyzing = false
            self.analysisTimedOut = true
            self.sightingListener?.remove()
            self.sightingListener = nil
            self.uploadSuccess = true
        }
    }

    /// Throws away the current take (file included) so a fresh one can be recorded.
    func retake() {
        stopRecording()
        clearIdentification()
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
        recordingSeconds = 0
        hasRecording = false
        meterLevel = 0
        notes = ""
        error = nil
        importNotice = nil
    }

    func reset() {
        noBirdDetected = false
        importNotice = nil
        stopRecording()
        clearIdentification()
        sightingListener?.remove()
        sightingListener = nil
        recordingURL = nil
        recordingSeconds = 0
        aiSuggestion = nil
        aiConfidence = nil
        aiAdditionalSuggestions = []
        error = nil
        uploadSuccess = false
        hasRecording = false
        isAnalyzing = false
        analysisTimedOut = false
    }
}
