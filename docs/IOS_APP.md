# iOS App

## Overview

The BioMap iOS app is built with **SwiftUI** targeting **iOS 17+**. It is the primary interface for citizen scientists to submit sightings, annotate the community dataset, and receive on-device bird identification powered by a continuously updated CoreML model.

---

## Requirements

| Requirement | Minimum |
|---|---|
| iOS | 17.0 |
| Xcode | 15.0 |
| Swift | 5.9 |
| Device | iPhone with camera (camera features); simulator works for browsing |

---

## Project Structure

```
ios/BioMap/BioMap/
├── App/
│   ├── BioMapApp.swift          Entry point, @main
│   ├── AppEnvironment.swift      Auth state, shared via @EnvironmentObject
│   └── ContentView.swift         4-tab shell + ProfileView
│
├── Models/
│   └── Sighting.swift            All Codable structs: Sighting, SightingDetail,
│                                 AnnotationItem, LeaderboardEntry, ModelVersionInfo
│
├── Networking/
│   ├── APIClient.swift           All REST calls; battery-efficient URLSession; multipart upload builder
│   └── UploadQueue.swift         Offline persistence; stores image file paths, not base64
│
├── ML/
│   ├── BirdClassifier.swift      CoreML + Vision inference; cached model + VNCoreMLModel
│   └── ModelManager.swift        Model version check, download, cache management
│
├── Views/
│   ├── Auth/
│   │   └── LoginView.swift       Register + login form
│   ├── Camera/
│   │   ├── CameraView.swift      Main capture UI, photo library, live camera; GPS lifecycle
│   │   └── CameraViewModel.swift GPS (conditional) + AI inference + upload + offline queueing
│   ├── Map/
│   │   └── SightingMapView.swift MapKit map with debounced bbox-filtered pins
│   ├── Sighting/
│   │   ├── SightingDetailView.swift  Photo, AI suggestion, annotations list
│   │   └── AnnotationView.swift      Species annotation form
│   └── Leaderboard/
│       └── LeaderboardView.swift     Top annotators ranked list
│
├── Info.plist                    Privacy strings, background modes
└── BioMap.entitlements          Sandbox + network + camera + location caps
```

---

## Key Components

### AppEnvironment

`AppEnvironment` is an `ObservableObject` injected at the root of the view hierarchy via `.environmentObject()`. It holds the JWT token and username, persisted in `UserDefaults`.

```swift
@Published var token: String? {
    didSet { UserDefaults.standard.set(token, forKey: "token") }
}
```

When `token` is `nil`, the app shows `LoginView`. When set, it transitions to the main `ContentView` tab shell.

---

### APIClient

A singleton that wraps all network calls. All calls are `async throws` using a custom battery-efficient `URLSession` configured with `waitsForConnectivity = true` and a 60-second resource timeout.

`waitsForConnectivity` means failed requests are held by the OS until connectivity is available rather than immediately retrying, which avoids repeatedly waking the radio when offline.

Key design decisions:
- `batteryEfficientSession` (module-level constant) used for all `data()` calls instead of `URLSession.shared`
- Multipart form data is built manually (no external dependency)
- JWT token is read from `UserDefaults` on every call — no separate token storage
- The client does not retry; retry logic lives in `UploadQueue`
- All force-unwraps replaced with `guard let` + typed `APIError` throws; HTTP 4xx/5xx surfaced via `checkStatus()`

To point the app at a different server, change `baseURL`:

```swift
APIClient.shared.baseURL = "https://api.biomap.app"
```

---

### UploadQueue

An `actor` (Swift concurrency-safe) that persists pending uploads across app restarts. When an upload fails, `CameraViewModel.saveImageToTemp()` writes the JPEG to the app's caches directory and stores the **file path** in `UserDefaults` as a `[PendingUpload]` array.

Storing file paths instead of base64-encoded strings avoids 33% data size inflation and the CPU cost of encoding/decoding large JPEG payloads.

```swift
// Enqueue on failure — path written to caches/pending_uploads/
await UploadQueue.shared.enqueue(PendingUpload(
    imagePath: fileURL.path,
    latitude: location.coordinate.latitude,
    longitude: location.coordinate.longitude,
    notes: notes
))

// Flushed on app launch (BioMapApp.swift)
await UploadQueue.shared.flushIfNeeded()
```

Items that succeed are removed and their image files deleted from disk. Items that still fail remain in the queue for the next attempt.

---

### BirdClassifier

Uses `VNCoreMLModel` + `VNCoreMLRequest` to run the downloaded CoreML model on a `CGImage`. Returns the top-1 classification:

```swift
let result = await BirdClassifier.shared.classify(image: capturedImage)
// result?.species == "American Robin"
// result?.confidence == 0.87
```

**Caching** — `VNCoreMLModel` is expensive to construct. `BirdClassifier` caches it alongside the model version string and only rebuilds it when `ModelManager` signals a version change via `invalidateCache()`. The underlying `MLModel` is similarly cached in `ModelManager` and only reloaded from disk when the version changes.

**Background queue** — `VNImageRequestHandler.perform()` runs on a dedicated `DispatchQueue` at `.userInitiated` QoS, not on the main actor. This keeps inference off the UI thread and allows the OS to schedule it at a lower power level than main-thread work.

If no model has been downloaded yet, `classify()` returns `nil` and the UI simply hides the AI suggestion section.

---

### ModelManager

On every app launch (triggered from `BioMapApp.body`):

1. `GET /model/version` → compare remote version string with `UserDefaults["model_version"]`
2. If different: `GET /model/download` → get presigned URL
3. `URLSession.download(from:)` → downloads to a temp file
4. Unzip `.mlpackage.zip` → `Documents/BirdClassifier.mlpackage` (via ZIPFoundation)
5. Delete the zip file after extraction to free disk space
6. Invalidate `ModelManager.cachedModel` and call `BirdClassifier.shared.invalidateCache()` so the next inference picks up the new model
7. Store new version string in `UserDefaults`

The download is silent — no UI feedback. The updated model is used on the next `BirdClassifier.classify()` call.

---

### CameraView + LiveCameraVC

The camera flow has two paths:

**Photo Library** — `UIImagePickerController` wrapped in `PhotoPickerView` (a `UIViewControllerRepresentable`).

**Live Camera** — `AVCaptureSession` with `AVCapturePhotoOutput`, implemented in `LiveCameraVC` (a `UIViewController` subclass). Presented via `NavigationLink` with a custom `UIViewControllerRepresentable` bridge.

`AVCaptureSession.stopRunning()` is called in `viewWillDisappear` to stop the camera hardware immediately when the user navigates back. Leaving the session running burns CPU and camera power for no benefit.

Both paths call `vm.setImage(_:)` which sets `capturedImage` and immediately fires `BirdClassifier.classify()`.

---

### CameraViewModel

Orchestrates the capture → classify → upload flow. GPS is managed conditionally:

- `startLocationUpdates()` / `stopLocationUpdates()` are called from `CameraView`'s `onAppear` / `onDisappear` — GPS hardware is completely off when the Report tab is not visible
- `desiredAccuracy = kCLLocationAccuracyHundredMeters` — sufficient for a map pin; avoids the power cost of full GPS lock
- `distanceFilter = 50` — suppresses updates for movements under 50 metres, reducing unnecessary wake-ups

On upload failure, `saveImageToTemp()` writes the compressed JPEG to `caches/pending_uploads/` and the path is handed to `UploadQueue`.

---

### SightingMapView

Uses the SwiftUI `Map` view with `Annotation` markers. Region-based fetching is **debounced** — `scheduleRegionLoad(_:)` cancels any pending `Task` and waits 600ms before firing a network request. This means rapid panning or zooming produces only one network call after the user settles, not one per frame.

```swift
func scheduleRegionLoad(_ region: MKCoordinateRegion) {
    debounceTask?.cancel()
    debounceTask = Task {
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        await loadForRegion(region)
    }
}
```

Tapping a pin opens `SightingDetailView` as a sheet.

---

## Adding the Xcode Project

Since this repo ships source files, create the Xcode project manually:

1. Open Xcode → **File → New → Project → iOS → App**
2. Set: Product Name `BioMap`, Bundle ID `com.birdradar.app`, Interface `SwiftUI`, Language `Swift`
3. Delete the default `ContentView.swift` that Xcode generates
4. Drag the `ios/BioMap/BioMap/` folder into the Project Navigator → **Add files to "BioMap"**, check **Create groups**, check **Add to target: BioMap**
5. In the project editor → **Info** tab, add:
   - `NSCameraUsageDescription`
   - `NSLocationWhenInUseUsageDescription`
   - `NSPhotoLibraryUsageDescription`
6. In **Signing & Capabilities**, add the entitlements from `BioMap.entitlements`
7. **File → Add Package Dependencies** and resolve `ios/BioMap/Package.swift` to pull in ZIPFoundation

---

## Permissions Required

| Permission | Usage |
|---|---|
| Camera (`NSCameraUsageDescription`) | Photographing birds via `AVCaptureSession`; session stopped immediately when camera view exits |
| Location When In Use (`NSLocationWhenInUseUsageDescription`) | Geotagging sightings; active **only** while Report tab is visible; uses `kCLLocationAccuracyHundredMeters` and 50m distance filter |
| Photo Library (`NSPhotoLibraryUsageDescription`) | Uploading existing photos via `UIImagePickerController` |

---

## Offline Behaviour

| Scenario | Behaviour |
|---|---|
| No network on launch | Cached sightings not shown (no local cache in v1.0); map is empty |
| Photo captured offline | JPEG saved to `caches/pending_uploads/`; path queued in `UploadQueue`; retried on next launch; file deleted after successful upload |
| Annotation submitted offline | Fails with error toast; no offline queue (v1.0 limitation) |
| Model download fails | App continues with previous cached model (or no AI suggestion if first run) |

---

## Configuration

Server URL is set in `APIClient.swift`:

```swift
var baseURL = "http://localhost:8000"
```

GPS accuracy and distance filter are set in `CameraViewModel.init()`:

```swift
locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
locationManager.distanceFilter = 50
```

For production, `baseURL` should be set from a build scheme environment variable or `xcconfig` file rather than hardcoded.
