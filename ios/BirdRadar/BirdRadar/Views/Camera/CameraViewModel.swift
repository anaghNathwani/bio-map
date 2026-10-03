import SwiftUI
import AVFoundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class CameraViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var capturedImage: UIImage?
    /// Top classification result — used for the upload payload and the primary badge.
    @Published var aiSuggestion: ClassificationResult?
    /// Top-3 on-device results shown as alternatives in the UI.
    @Published var aiCandidates: [ClassificationResult] = []
    /// Additional distinct species found via saliency-region detection
    /// (MultiBirdDetector) — birds in the same frame beyond aiSuggestion.
    @Published var aiAdditionalSuggestions: [BirdCandidate] = []
    /// True once on-device classification has actually finished running for
    /// the current photo (regardless of outcome) — lets the UI distinguish
    /// "still classifying" from "classified, but not confident it's a bird"
    /// instead of both looking like silence.
    @Published var didClassify = false
    @Published var notes = ""
    @Published var isUploading = false
    @Published var uploadSuccess = false
    @Published var error: String?
    /// Snapshot of the sighting + AI suggestion taken right before upload() clears
    /// state, so the post-upload AI review card has something to show.
    @Published var lastUploadedSightingID: String?
    @Published var lastAISuggestion: ClassificationResult?
    @Published var lastAdditionalSuggestions: [BirdCandidate] = []

    private let locationManager = CLLocationManager()
    private(set) var lastLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        // Hundred-metre accuracy is sufficient for a bird sighting pin on a map
        // and uses far less GPS power than the default kCLLocationAccuracyBest.
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50 // only update after moving 50m — suppresses noise
        locationManager.requestWhenInUseAuthorization()
    }

    /// Call when the camera/report tab becomes active.
    func startLocationUpdates() {
        locationManager.startUpdatingLocation()
    }

    /// Call when the camera/report tab goes inactive to stop GPS hardware.
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }

    func setLastLocation(_ location: CLLocation) {
        lastLocation = location
    }

    func setImage(_ image: UIImage) {
        capturedImage = image
        aiSuggestion = nil
        aiCandidates = []
        aiAdditionalSuggestions = []
        didClassify = false
        Task {
            let results = await BirdClassifier.shared.classifyTopN(image: image, count: 3)
            aiCandidates = results
            aiSuggestion = results.first
            aiAdditionalSuggestions = await MultiBirdDetector.detectAdditional(
                in: image, primarySpecies: results.first?.species
            )
            didClassify = true
        }
    }

    /// Discards the current photo and its AI results so a new one can be taken.
    func retake() {
        capturedImage = nil
        aiSuggestion = nil
        aiCandidates = []
        aiAdditionalSuggestions = []
        didClassify = false
        notes = ""
        error = nil
    }

    func upload() async {
        guard let image = capturedImage,
              let data = image.jpegData(compressionQuality: 0.85) else {
            error = "No photo selected"
            return
        }
        // Use last known location, or fall back to a default if GPS hasn't fixed yet
        // (simulator never gets GPS — real device will have a proper fix)
        let location = lastLocation ?? CLLocation(latitude: 37.7749, longitude: -122.4194)

        isUploading = true
        error = nil
        let sightingID = UUID().uuidString
        do {
            let (photoURL, thumbURL, fallbackURL) = try await FirebaseService.shared.uploadImage(data, sightingID: sightingID)
            _ = try await FirebaseService.shared.createSighting(
                photoURL: photoURL,
                thumbnailURL: thumbURL,
                audioURL: nil,
                photoFallbackURL: fallbackURL,
                mediaType: "photo",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                notes: notes.isEmpty ? nil : notes,
                aiSpecies: aiSuggestion?.species,
                aiConfidence: aiSuggestion.map { Double($0.confidence) },
                aiAdditionalSpecies: aiAdditionalSuggestions
            )
            lastUploadedSightingID = sightingID
            lastAISuggestion = aiSuggestion
            lastAdditionalSuggestions = aiAdditionalSuggestions
            uploadSuccess = true
            capturedImage = nil
            aiSuggestion = nil
            aiCandidates = []
            aiAdditionalSuggestions = []
            didClassify = false
            notes = ""
        } catch {
            self.error = "Upload failed: \(error.localizedDescription)"
        }
        isUploading = false
    }

    private func saveImageToTemp(data: Data) -> URL? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("[CameraViewModel] Failed to save pending image: \(error)")
            return nil
        }
    }

    // CLLocationManagerDelegate
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.setLastLocation(location) }
    }
}
