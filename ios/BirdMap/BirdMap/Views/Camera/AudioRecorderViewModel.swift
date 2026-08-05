import SwiftUI
import AVFoundation
import CoreLocation
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
    @Published var meterLevel: Float = 0
    @Published var notes = ""
    @Published var hasRecording = false

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var countTimer: Timer?
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
                aiSpecies: aiSuggestion,
                aiConfidence: aiConfidence
            )
            uploadSuccess = true
            notes = ""
            hasRecording = false
            recordingURL = nil
            recordingSeconds = 0
        } catch {
            self.error = "Upload failed: \(error.localizedDescription)"
        }
        isUploading = false
    }

    func reset() {
        stopRecording()
        recordingURL = nil
        recordingSeconds = 0
        aiSuggestion = nil
        aiConfidence = nil
        error = nil
        uploadSuccess = false
        hasRecording = false
    }
}
