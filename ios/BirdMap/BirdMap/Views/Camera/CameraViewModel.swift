import SwiftUI
import AVFoundation
import CoreLocation

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
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func nlocations(_ location: CLLocation) {
        lastLocation = location
    }

    func nothingCapture(_ image: UIImage) {
        capturedImage = image
        Task {
            aiSuggestion = await BirdClassifier.shared.classify(image: image)
        }
    }

    func upload() async {
        guard let image = capturedImage,
              let location = lastLocation,
              let data = image.jpegData(compressionQuality: 0.85) else {
            error = "Missing image or location"
            return
        }

        isUploading = true
        error = nil
        do {
            _ = try await APIClient.shared.uploadSighting(
                imageData: data,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                notes: notes.isEmpty ? nil : notes
            )
            uploadSuccess = true
            capturedImage = nil
            aiSuggestion = nil
            notes = ""
        } catch {
            // Queue for retry when offline
            let pending = UploadQueue.PendingUpload(
                imageDataBase64: data.base64EncodedString(),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                notes: notes.isEmpty ? nil : notes
            )
            UploadQueue.shared.enqueue(pending)
            self.error = "Saved offline — will upload when connected."
        }
        isUploading = false
    }

    // CLLocationManagerDelegate
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in lastLocation = locations.last }
    }
}
