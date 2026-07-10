import SwiftUI
import AVFoundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class CameraViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var capturedImage: UIImage?
    @Published var aiSuggestion: ClassificationResult?
    @Published var notes = ""
    @Published var isUploading = false
    @Published var uploadSuccess = false
    @Published var error: String?

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
        Task {
            aiSuggestion = await BirdClassifier.shared.classify(image: image)
        }
    }

    func upload() async {
        guard let image = capturedImage,
              let data = image.jpegData(compressionQuality: 0.85) else {
            error = "No photo selected"
            return
        }

        // Use last known location; fall back to 0,0 so the sighting isn't lost.
        // The server stores whatever coordinates we send, so a missing GPS fix
        // results in a pin at the origin rather than a silently dropped sighting.
        let latitude = lastLocation?.coordinate.latitude ?? 0
        let longitude = lastLocation?.coordinate.longitude ?? 0
        if lastLocation == nil {
            error = "GPS fix unavailable — sighting will be saved without exact location."
        }

        isUploading = true
        do {
            _ = try await APIClient.shared.uploadSighting(
                imageData: data,
                latitude: latitude,
                longitude: longitude,
                notes: notes.isEmpty ? nil : notes
            )
            uploadSuccess = true
            capturedImage = nil
            aiSuggestion = nil
            notes = ""
            error = nil
        } catch {
            if let fileURL = saveImageToTemp(data: data) {
                let pending = UploadQueue.PendingUpload(
                    imagePath: fileURL.path,
                    latitude: latitude,
                    longitude: longitude,
                    notes: notes.isEmpty ? nil : notes
                )
                await UploadQueue.shared.enqueue(pending)
            }
            self.error = "Saved offline — will upload when connected."
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
