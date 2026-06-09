# iOS App

## Overview

The BirdMap iOS app is built with **SwiftUI** targeting **iOS 17+**. It is the primary interface for citizen scientists to submit sightings, annotate the community dataset, and receive on-device bird identification powered by a continuously updated CoreML model.

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
ios/BirdMap/BirdMap/
├── App/
│   ├── BirdMapApp.swift          Entry point, @main
│   ├── AppEnvironment.swift      Auth state, shared via @EnvironmentObject
│   └── ContentView.swift         4-tab shell + ProfileView
│
├── Models/
│   └── Sighting.swift            All Codable structs: Sighting, SightingDetail,
│                                 AnnotationItem, LeaderboardEntry, ModelVersionInfo
│
├── Networking/
│   ├── APIClient.swift           All REST calls; multipart upload builder
│   └── UploadQueue.swift         Offline persistence (UserDefaults)
│
├── ML/
│   ├── BirdClassifier.swift      CoreML + Vision inference
│   └── ModelManager.swift        Model version check + background download
│
├── Views/
│   ├── Auth/
│   │   └── LoginView.swift       Register + login form
│   ├── Camera/
│   │   ├── CameraView.swift      Main capture UI, photo library, live camera
│   │   └── CameraViewModel.swift GPS + AI inference + upload orchestration
│   ├── Map/
│   │   └── SightingMapView.swift MapKit map with bbox-filtered pins
│   ├── Sighting/
│   │   ├── SightingDetailView.swift  Photo, AI suggestion, annotations list
│   │   └── AnnotationView.swift      Species annotation form
│   └── Leaderboard/
│       └── LeaderboardView.swift     Top annotators ranked list
│
├── Info.plist                    Privacy strings, background modes
└── BirdMap.entitlements          Sandbox + network + camera + location caps
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

A singleton that wraps all network calls. All calls are `async throws` using `URLSession`.

Key design decisions:
- Multipart form data is built manually (no external dependency)
- JWT token is read from `UserDefaults` on every call — no separate token storage
- The client does not retry; retry logic lives in `UploadQueue`

To point the app at a different server, change `baseURL`:

```swift
APIClient.shared.baseURL = "https://api.birdmap.app"
```

---

### UploadQueue

When an upload fails (network error, timeout), the image is base64-encoded and serialised to `UserDefaults` as a `[PendingUpload]` array. On next launch, `flushIfNeeded()` is called and retries each queued item.

```swift
// Enqueue on failure
UploadQueue.shared.enqueue(PendingUpload(
    imageDataBase64: data.base64EncodedString(),
    latitude: location.coordinate.latitude,
    longitude: location.coordinate.longitude,
    notes: notes
))

// Call on app launch / foreground
await UploadQueue.shared.flushIfNeeded()
```

Items that succeed are removed; items that still fail remain in the queue for the next attempt.

---

### BirdClassifier

Uses `VNCoreMLModel` + `VNCoreMLRequest` to run the downloaded CoreML model on a `CGImage`. Returns the top-1 classification:

```swift
let result = await BirdClassifier.shared.classify(image: capturedImage)
// result?.species == "American Robin"
// result?.confidence == 0.87
```

This runs asynchronously on a background queue via `VNImageRequestHandler`. The UI updates when the result comes back via `@MainActor`.

If no model has been downloaded yet, `classify()` returns `nil` and the UI simply hides the AI suggestion section.

---

### ModelManager

On every app launch (triggered from `BirdMapApp.body`):

1. `GET /model/version` → compare remote version string with `UserDefaults["model_version"]`
2. If different: `GET /model/download` → get presigned URL
3. `URLSession.download(from:)` → downloads to temp file
4. Unzip `.mlpackage.zip` → `Documents/BirdClassifier.mlpackage`
5. Store new version string in `UserDefaults`

The download is silent — no UI feedback. The updated model is used on the next `BirdClassifier.classify()` call.

> **Note:** The `unzip` step uses `Process` + `/usr/bin/unzip`. For App Store distribution, replace with [ZipFoundation](https://github.com/weichsel/ZIPFoundation) via Swift Package Manager, as `Process` is not available on iOS (it is macOS-only). The architecture of `ModelManager` makes this a one-line swap.

---

### CameraView + LiveCameraVC

The camera flow has two paths:

**Photo Library** — `UIImagePickerController` wrapped in `PhotoPickerView` (a `UIViewControllerRepresentable`).

**Live Camera** — `AVCaptureSession` with `AVCapturePhotoOutput`, implemented in `LiveCameraVC` (a `UIViewController` subclass). Presented via `NavigationLink` with a custom `UIViewControllerRepresentable` bridge.

Both paths call `vm.nothingCapture(_:)` which sets `capturedImage` and immediately fires `BirdClassifier.classify()`.

---

### SightingMapView

Uses the SwiftUI `Map` view with `Annotation` markers. The map calls `vm.loadForRegion()` every time the camera position changes (`onMapCameraChange(frequency: .onEnd)`), fetching only the sightings within the current viewport bounding box. This prevents loading thousands of global sightings at once.

Tapping a pin opens `SightingDetailView` as a sheet.

---

## Adding the Xcode Project

Since this repo ships source files, create the Xcode project manually:

1. Open Xcode → **File → New → Project → iOS → App**
2. Set: Product Name `BirdMap`, Bundle ID `com.birdmap.app`, Interface `SwiftUI`, Language `Swift`
3. Delete the default `ContentView.swift` that Xcode generates
4. Drag the `ios/BirdMap/BirdMap/` folder into the Project Navigator → **Add files to "BirdMap"**, check **Create groups**, check **Add to target: BirdMap**
5. In the project editor → **Info** tab, add:
   - `NSCameraUsageDescription`
   - `NSLocationWhenInUseUsageDescription`
   - `NSPhotoLibraryUsageDescription`
6. In **Signing & Capabilities**, add the entitlements from `BirdMap.entitlements`

---

## Permissions Required

| Permission | Usage |
|---|---|
| Camera (`NSCameraUsageDescription`) | Photographing birds via `AVCaptureSession` |
| Location When In Use (`NSLocationWhenInUseUsageDescription`) | Geotagging sightings via `CLLocationManager` |
| Photo Library (`NSPhotoLibraryUsageDescription`) | Uploading from existing photos via `UIImagePickerController` |

---

## Offline Behaviour

| Scenario | Behaviour |
|---|---|
| No network on launch | Cached sightings not shown (no local cache in v1.0); map is empty |
| Photo captured offline | UploadQueue persists it; uploaded on next successful connection |
| Annotation submitted offline | Fails with error toast; no offline queue (v1.0 limitation) |
| Model download fails | App continues with previous model (or no model if first run) |

---

## Configuration

All server configuration is in `APIClient.swift`:

```swift
var baseURL = "http://localhost:8000"
```

For production, this should be set from a configuration file or build scheme environment variable rather than hardcoded.
