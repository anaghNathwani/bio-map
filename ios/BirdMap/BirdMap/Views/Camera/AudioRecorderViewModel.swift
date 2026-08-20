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
            isRecording = true
            recordingSeconds = 0
            error = nil

            countTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recordingSeconds += 1 }
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
        recorder?.stop()
        meterTimer?.invalidate()
        countTimer?.invalidate()
        isRecording = false
        meterLevel = 0
        hasRecording = recordingURL != nil
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    func upload() async {
        guard let url = recordingURL, let data = try? Data(contentsOf: url) else {
            error = "No recording found"; return
        }
        let location = lastLocation ?? CLLocation(latitude: 37.7749, longitude: -122.4194)

        isUploading = true
        error = nil
        let sightingID = UUID().uuidString

        do {
            let audioURL = try await FirebaseService.shared.uploadAudio(data, sightingID: sightingID, filename: url.lastPathComponent)
            _ = try await FirebaseService.shared.createSighting(
                photoURL: nil,
                thumbnailURL: nil,
                audioURL: audioURL,
                mediaType: "audio",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                notes: notes.isEmpty ? nil : notes,
                aiSpecies: nil,
                aiConfidence: nil
            )
            notes = ""
            hasRecording = false
            recordingURL = nil
            recordingSeconds = 0
            lastUploadedSightingID = sightingID
            startAnalyzing(sightingID: sightingID)
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

    func reset() {
        stopRecording()
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
