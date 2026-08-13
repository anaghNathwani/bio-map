# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BirdMap is a citizen science iOS app for bird sighting collection, community annotation, and ML bird identification (on-device for photos, server-side for audio). The **live backend is Firebase** (Auth, Firestore, Storage) — the repo also contains a FastAPI Python backend (`backend/`) that is legacy/optional (Google Vision proxy + Wikipedia/eBird info lookups only; not deployed, not required) and a self-hosted PyTorch ML pipeline (`ml_pipeline/`) that reads/writes Firestore directly via the Admin SDK.

## Commands

### iOS
```bash
# Build and run from Terminal (NOT by opening the .xcodeproj — see gotchas below)
cd birdmap/ios/BirdMap
xcodebuild -scheme BirdMap -destination 'id=<simulator-udid>' -configuration Debug build
```

### ML Pipeline (self-hosted, talks directly to Firestore/Storage via the Admin SDK)
```bash
cd birdmap/ml_pipeline
pip install -r requirements.txt

# One-time bootstrap: produces the first real base model from iNaturalist photos
python train.py --bootstrap-common-birds

# Retrain on community annotations
python train.py --min-annotations 50

# Live audio ID (BirdNET) + annotation moderation — keep running continuously
python live_service.py
```
Needs Firebase Admin credentials: `--service-account <path>`, `GOOGLE_APPLICATION_CREDENTIALS`, or Application Default Credentials (`gcloud auth application-default login`). See `docs/ML_PIPELINE.md`.

### Backend (legacy/optional — not deployed, not required for the app to function)
```bash
cd birdmap && docker-compose up -d
```
Only used for the Google Vision photo-ID proxy and Wikipedia/eBird bird-info lookups, both of which have working fallbacks/are non-critical when this isn't running.

## Architecture

### iOS App (`ios/BirdMap/BirdMap/`)

**Entry point:** `App/BirdMapApp.swift` → routes to `LoginView` or `ContentView` (TabView) based on Firebase Auth state (`AppEnvironment`).

**State:** `AppEnvironment` is a single `@EnvironmentObject` holding the Firebase `user`/`username`, injected at the root.

**Networking:** `Networking/FirebaseService.swift` is the primary data layer — all auth, sightings, annotations, and leaderboard reads/writes go through Firestore/Storage/Auth directly. `Networking/APIClient.swift` only proxies the optional Google Vision bird-ID call and Wikipedia bird-info lookups; it is not used for auth or sighting data.

**Offline queue:** `Networking/UploadQueue.swift` — Swift `actor`. Failed uploads are persisted as JPEG paths in `caches/pending_uploads/` with file paths stored in `UserDefaults`. Flushed on app launch.

**ML:** `ML/BirdClassifier.swift` wraps a CoreML `VNCoreMLRequest` on a `.userInitiated` background queue — on-device photo classification. `ML/ModelManager.swift` queries the `model_versions` Firestore collection for the active photo model, downloads the `.mlpackage.zip` from Firebase Storage if the version changed, unzips with ZIPFoundation, then invalidates the `BirdClassifier` model cache. Audio classification is server-side (BirdNET via `ml_pipeline/live_service.py`) — the app uploads the recording and listens for the sighting doc's `aiSpeciesSuggestion` to populate.

**Views:**
- `Views/Auth/LoginView.swift` — login + register in one form, toggled by `isRegistering`
- `Views/Camera/CameraView.swift` + `CameraViewModel.swift` — photo capture (live AVFoundation or library picker), on-device AI inference, upload flow, post-upload AI review (Right/Wrong/Unsure)
- `Views/Camera/AIPredictionCard.swift` — shared prediction + reference-photo + review card, used by both photo and audio flows
- `Views/Camera/AudioRecorderView.swift` + `AudioRecorderViewModel.swift` — recording, upload, "analyzing" wait state, then the same AI review flow once BirdNET's server-side result lands
- `Views/Map/SightingMapView.swift` — MapKit annotations with 600ms debounced bbox fetch on camera change
- `Views/Sighting/SightingDetailView.swift` — photo/audio, AI suggestion, community annotations list (with a "flagged" badge for moderated annotations)
- `Views/Sighting/AnnotationView.swift` — species/behavior/confidence form; can be pre-filled from an AI review verdict
- `Views/Leaderboard/LeaderboardView.swift` — ranked annotators list

### ML Pipeline (`ml_pipeline/`)

Self-hosted Python scripts using the Firebase Admin SDK (`firestore_client.py`) — no Cloud Functions, no Blaze-only compute required for the scripts themselves (Firebase Storage itself does need Blaze, for uploads generally):
- `train.py` — fetches plurality-voted, non-flagged photo annotations from Firestore, fine-tunes EfficientNet-B0 (PyTorch, ImageNet1K pretrained), exports to `.mlpackage` via `coremltools`, uploads to Firebase Storage, registers the new version in `model_versions`. `--bootstrap-common-birds` seeds from iNaturalist when there's little/no annotation data yet.
- `live_service.py` — long-running process with two Firestore realtime listeners: BirdNET audio analysis (writes `aiSpeciesSuggestion`/`aiConfidence` onto audio sightings) and annotation moderation (writes `moderation`/`moderationScore` onto new annotations using a local sentence-embedding model).

Full details: `docs/ML_PIPELINE.md`.

### Key data flows

- **Sighting upload:** `CameraViewModel.upload()` / `AudioRecorderViewModel.upload()` → `FirebaseService.uploadImage/uploadAudio` + `createSighting` → Firebase Storage + Firestore. On failure, `UploadQueue` persists to disk and retries on next launch.
- **Model update:** App launch → `ModelManager.checkForUpdate()` → query `model_versions` → download zip from Storage if version changed → unzip to `Documents/BirdClassifier.mlpackage` → `BirdClassifier` picks it up on next inference.
- **AI review loop:** Prediction shown (on-device for photo, async via `live_service.py` for audio) → user taps Right/Wrong/Unsure → `AnnotationView` pre-filled accordingly → `FirebaseService.submitAnnotation()` writes to Firestore with `reviewOfAI` set.
- **Moderation loop:** New annotation written → `live_service.py`'s moderation listener classifies it → `moderation`/`moderationScore` written back → flagged annotations are excluded from `train.py`'s plurality voting.
- **Self-learning loop:** Annotations accumulate → `python train.py` (manual or `--watch`) → new model registered in `model_versions` → app downloads it on next launch.
