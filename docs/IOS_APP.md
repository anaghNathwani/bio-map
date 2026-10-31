# iOS App

## Overview

The BioMap iOS app is built with **SwiftUI** for **iOS 17+**, iPhone only. Citizen scientists use it to photograph or record
birds, get an on-device species suggestion, submit sightings to a shared map, and confirm or correct other people's IDs.
Auth, data and media all go through **Firebase** (Auth + Firestore) directly; there is no backend to deploy. See
`CLAUDE.md` for the architecture and `docs/ML_PIPELINE.md` for the models.

The project is generated from `ios/BioMap/project.yml` with **XcodeGen**, so edit `project.yml`, not the `.xcodeproj`
(regenerating overwrites hand-edits made only in Xcode). It also uses **CocoaPods** (`TensorFlowLiteSwift`) and Swift Package
Manager (Firebase, GoogleSignIn, ZIPFoundation), so always open **`BioMap.xcworkspace`**.

---

## Requirements

| Requirement | Minimum |
|---|---|
| iOS | 17.0 (the Lock Screen corner controls need iOS 18) |
| Xcode | 16 |
| Swift | 5.9 |
| Tools | `xcodegen`, `pod` (CocoaPods) |
| Device | iPhone with a camera; the simulator works for browsing but has no camera |

## Building and running

```bash
cd ios/BioMap
xcodegen generate                 # regenerates the project and re-runs `pod install`
open BioMap.xcworkspace           # or build from Terminal:
xcodebuild -workspace BioMap.xcworkspace -scheme BioMap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build
```

To run on your own iPhone, plug it in, turn on Developer Mode (Settings → Privacy & Security), choose it as the destination
and press ⌘R. Re-run after changes. To put a build in front of testers, see [TESTFLIGHT.md](TESTFLIGHT.md).

**Versions** are set once in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) and shared by the app and the
widget extension. Bump the build number for every upload.

---

## Project structure

```
ios/BioMap/
├── project.yml                       XcodeGen spec: targets, versions, bundle IDs, signing team
├── Podfile                           TensorFlowLiteSwift
├── BioMap/                           the app target (com.biomap.BioMap)
│   ├── App/
│   │   ├── BioMapApp.swift           entry point; Firebase + Google Sign-In setup; URL routing
│   │   ├── AppEnvironment.swift      auth state; DeepLink (widget / control / URL requests)
│   │   └── ContentView.swift         tab shell (Map, Report, Leaders, Profile); consumes deep links
│   ├── Models/                       Sighting, SightingDetail, AnnotationItem, BirdInfo ...
│   ├── Networking/
│   │   ├── FirebaseService.swift     the data layer: auth, sightings, annotations, leaderboard, feedback, media
│   │   ├── APIClient.swift           Wikipedia bird info + the optional (dead) Vision proxy
│   │   ├── UploadQueue.swift         offline retry queue (actor)
│   │   └── DataURI.swift             base64 data-URI decoding for photo/audio
│   ├── ML/
│   │   ├── BirdClassifier.swift      photo species (AIY Birds V1 via TensorFlow Lite)
│   │   ├── BirdNETClassifier.swift   call identification (BirdNET V2.4 + location model, TFLite)
│   │   ├── MultiBirdDetector.swift   several birds in one photo (Vision saliency / optional detector)
│   │   ├── BirdDetector.swift        the optional CoreML object detector
│   │   ├── AnnotationModerator.swift on-device "is this a real bird name" check
│   │   ├── ModelManager.swift        model updates from Firestore chunks
│   │   └── Bundled/                  the shipped .tflite models and label files
│   └── Views/
│       ├── Auth/LoginView.swift
│       ├── Camera/                   CameraView (+ live camera), AudioRecorderView, review cards,
│       │                             CameraControls.swift (zoom bar, shutter, focus square)
│       ├── Map/                      SightingMapView, SightingListView
│       ├── Sighting/                 SightingDetailView, AnnotationView
│       ├── Bird/BirdInfoView.swift
│       ├── Leaderboard/LeaderboardView.swift
│       ├── Profile/                  ProfileView, FeedbackView
│       └── Common/                   Theme.swift, BioLoader.swift, OrganismData.swift (generated)
└── BioMapWidgets/                    the widget extension (com.biomap.BioMap.Widgets)
    ├── BioMapWidgets.swift           the widget bundle
    ├── SightingsWidget.swift         home screen + Lock Screen widgets
    ├── Controls.swift                the two Lock Screen corner controls (iOS 18)
    └── ControlIntents.swift          their actions; ALSO compiled into the app (see below)
```

---

## Key components

### Design (`Theme.swift`)

The app uses the system look: San Francisco type, system background/label colours (so light, dark and accessibility settings
just work) and one blue accent (`#0071E3` light, `#0A84FF` dark). `ThemeColors` exposes `bg`, `bgRaised`, `fg`, `fgSoft`,
`accent`, `accentSoft` and `rule`. Shared pieces: `Tile` (rounded soft surface), `PillButtonStyle` (blue capsule button),
`Eyebrow`, `HairlineRule`, and `BirdMark` (the logo as a vector `Shape`). The website follows the same language
(`web/src/tailwind.css`).

### Loading animation (`BioLoader.swift`)

The brand bird morphs through other organisms down to single cells (butterfly, fish, leaf, jellyfish, amoeba, bacterium,
yeast, paramecium, diatom) and back, drawn as one blue line. Shapes are radius-versus-angle tables generated by
`web/scripts/gen_organisms.py` into `OrganismData.swift` and `web/src/lib/organisms.js`; edit the script, not the outputs.
It honours Reduce Motion (a still bird).

### Camera (`CameraView.swift`, `CameraControls.swift`)

The live camera (`LiveCameraVC`, a `UIViewController` bridged into SwiftUI) works like the native Camera app:

- It prefers the multi-lens virtual camera (triple, dual-wide, dual) so zoom hops between real lenses.
- A zoom bar above the shutter shows the same stops the native app does (for example `.5  1  2  3`); the active stop turns yellow
  and shows the exact zoom (`3.4×`). Tapping a stop ramps smoothly to it. Pinch zooms continuously (0.5× up to 15×).
- Haptic ticks as a pinch crosses a lens; tap-to-focus with the yellow square; a native-style shutter.
- The zoom maths (`CameraZoom`) is pure Swift, kept apart from AVFoundation so it can be tested without a camera.
- `AVCaptureSession.stopRunning()` runs in `viewWillDisappear` so the camera hardware stops when you leave.

The photo library path uses `PhotoPickerView` (`UIImagePickerController`). Both paths call `vm.setImage(_:)`, which runs the
on-device classifier.

### Report tab and deep links

`ContentView` owns the selected tab and the Report tab's Photo/Sound mode. Something outside the app can ask to land on a
screen by setting `AppEnvironment.pendingDeepLink` (`DeepLink`: `photo`, `sound`, `map`), which `ContentView` consumes once
the user is signed in. Two things set it:

- **URLs** `com.biomap.app://photo`, `://sound` and `://map` (`BioMapApp.onOpenURL`; anything else goes to Google Sign-In).
- **Lock Screen controls** via `ControlRoute` (see Widgets).

### Feedback (`FeedbackView.swift`)

Profile → "Report a bug or suggest a feature" writes to the write-only `feedback` Firestore collection through
`FirebaseService.submitFeedback`, attaching the app version, build, device model and iOS version. New reports are emailed by
`ml_pipeline/notify_waitlist_signups.py`.

### Widgets (`BioMapWidgets/`)

| Where | What |
|---|---|
| Home screen, small | Sighting count, how long ago the latest one was; tap opens the camera |
| Home screen, medium | The same, plus Photo and Sound buttons |
| Lock Screen, circular / rectangular / inline | Bird icon or "BioMap · 37 sightings"; tap opens the camera |
| Lock Screen corner buttons (iOS 18+) | "Photograph a bird" and "Record a bird call" controls (also in Control Center) |

- The count and latest time come from Firestore's REST API (`runAggregationQuery` / `runQuery` on `sightings`), which the
  security rules allow publicly, so there is **no App Group** and no sign-in. The widget bundles `GoogleService-Info.plist`
  for its API key, and refreshes about every 30 minutes.
- Tapping opens the app with a `com.biomap.app://` link.
- **The control intents must exist in the app too.** `ControlIntents.swift` is compiled into both targets: iOS runs an
  app-opening control's intent inside the app process, and when it only existed in the extension, tapping the control did
  nothing. The intent also leaves a `ControlRoute` hand-off that the app picks up, and returns an `OpenURLIntent` as a backup.
- Add one: touch and hold the home screen and tap **+**, or touch and hold the Lock Screen and tap **Customize**.

### Offline queue (`UploadQueue.swift`)

An `actor`. Failed photo uploads are written to `caches/pending_uploads/` as JPEG files, with the paths kept in `UserDefaults`,
and retried on the next launch; each file is deleted after a successful upload.

### Models (`ML/`)

See `docs/ML_PIPELINE.md` for what each model is. In short: photo ID is Google's AIY Birds V1, call ID is Cornell's BirdNET
V2.4 plus its location model, all run on the phone through TensorFlow Lite; annotation moderation is rules and string matching,
not a model. Copies are bundled in `ML/Bundled/`. `ModelManager` can ship a replacement through Firestore without an app
release.

---

## Permissions

| Permission | Usage |
|---|---|
| Camera | Photographing birds; the session stops when the camera view exits |
| Microphone | Recording calls for BirdNET |
| Location When In Use | Geotagging sightings and narrowing audio results; active only while the Report tab is visible (100 m accuracy, 50 m filter) |
| Photo Library | Choosing existing photos |

The privacy manifest (`PrivacyInfo.xcprivacy`) declares no tracking and the `UserDefaults` reason `CA92.1`. The app sets
`ITSAppUsesNonExemptEncryption` to false (standard HTTPS only).

## Offline behaviour

| Scenario | Behaviour |
|---|---|
| Identifying a bird | Works offline: both models run on the phone |
| Submitting a photo offline | Queued and retried at next launch |
| Submitting an annotation offline | Fails with an error; there is no offline queue for annotations |
| Model update fails | The app keeps the bundled / previously cached model |
| Widgets offline | Show the last data, or "–" with no data yet |

## Configuration

- **Firebase:** `BioMap/GoogleService-Info.plist` (and `REVERSED_CLIENT_ID` must match the Google URL scheme in `project.yml`).
- **`API_BASE_URL`:** `http://localhost:8000` in Debug and the legacy backend URL in Release; only the optional Vision proxy
  uses it.
- **Signing:** automatic, team `2JN5C47MQT`.
