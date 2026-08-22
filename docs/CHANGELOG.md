# Changelog

All notable changes to BirdMap are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

> Entries below referencing the ML training pipeline, `train.py`, or EfficientNet-B0 describe the original REST/Postgres-backed design, not the live Firebase-based app (see `CLAUDE.md`). The live app's actual training policy and trigger mechanism are documented in `docs/ML_PIPELINE.md`'s "Our in-house training policy" — a 500-annotation trigger now runs live via `ml_pipeline/check_training_trigger.py`, superseding the "webhook-triggered retraining" item below, which was never built under that name.

---

## [Unreleased]

### Planned for v1.1
- Species autocomplete via a curated species list endpoint
- Annotation offline queue (mirrors the sighting upload queue)
- Layer-freezing strategy in ML pipeline for small-dataset training runs
- ~~Webhook-triggered retraining when annotation count crosses a threshold~~ — superseded: a polling-based trigger (not a webhook) now runs live every 20 minutes, see `docs/ML_PIPELINE.md`

---

## [1.1.0] — Battery & Performance Pass

### Changed

**iOS App — Battery optimisations**
- `CLLocationManager` accuracy reduced to `kCLLocationAccuracyHundredMeters` with a 50m `distanceFilter` — sufficient for bird sighting pins; avoids the power cost of full GPS lock
- GPS now starts and stops with the Report tab (`onAppear` / `onDisappear`) via `startLocationUpdates()` / `stopLocationUpdates()` — GPS hardware is off whenever the Report tab is not visible
- `AVCaptureSession.stopRunning()` called in `LiveCameraVC.viewWillDisappear` — camera hardware no longer keeps running after navigating back
- `VNCoreMLModel` is now cached per model version in `BirdClassifier`; only rebuilt when `ModelManager` signals a new version via `invalidateCache()` — previously recreated on every inference call
- CoreML inference moved to a dedicated `DispatchQueue` at `.userInitiated` QoS — no longer runs on the main actor
- `MLModel` cached in `ModelManager` per version string; only loaded from disk when the version changes
- `URLSession.shared` replaced with `batteryEfficientSession` (`waitsForConnectivity = true`, 60s timeout) in `APIClient` — avoids hammering the radio when offline
- Map region fetch debounced 600ms via `Task.sleep` + `Task` cancellation in `scheduleRegionLoad()` — rapid panning no longer triggers one network request per movement

**iOS App — Offline queue**
- `UploadQueue` converted from `class` + `NSLock` to `actor` for Swift 6 concurrency safety
- Pending uploads now stored as JPEG file paths in `caches/pending_uploads/` instead of base64-encoded strings in `UserDefaults` — eliminates 33% size inflation and CPU cost of base64 encode/decode
- Image files are deleted from disk after successful upload

**iOS App — Model management**
- Zip file deleted from disk after extraction to free storage
- After a model update, `ModelManager` invalidates both its own `MLModel` cache and `BirdClassifier.cachedVNModel` so the next inference immediately uses the new model

**iOS App — Reliability**
- All `URLRequest` construction now `throws` on invalid URL instead of force-unwrapping
- `APIClient` exposes typed `APIError` enum (`invalidURL`, `missingField`, `httpError`) and `checkStatus()` — HTTP 4xx/5xx are now thrown, not silently decoded as garbage
- All response field accesses use `guard let` instead of `!` force-unwraps

**Swift Package Manager**
- Added `Package.swift` with ZIPFoundation `>= 0.9.19` dependency
- `ModelManager.unzip()` now uses `FileManager.unzipItem(at:to:)` — replaces the old stub that always threw an error (model downloading was non-functional before this)

**Backend**
- `db.refresh(annotation)` added after commit in `annotations.py` so returned `id` reflects the DB-generated UUID
- Status code constant `status.HTTP_400_BAD_REQUEST` used in `auth.py` instead of raw integer
- Missing `__init__.py` added to `app/`, `app/models/`, `app/services/`
- ORM models imported in `main.py` so SQLAlchemy registers all tables
- `lifespan` handler added to run `create_all` on startup — tables are now created automatically

**ML Pipeline**
- `best_state` initialised to pre-training weights — prevents `None` crash if no epoch improves validation accuracy
- CoreML normalisation `scale` fixed to `1/255` with per-channel `bias = -mean/std` — previous formula `1/255/sum(std)/3` produced incorrect image preprocessing
- `fetch_training_data()` wrapped in `try/except` in `main()` with a meaningful error message

---

## [1.0.0] — Initial Release

### Added

**iOS App**
- User registration and login with JWT authentication
- Bird sighting capture via device camera (AVFoundation `AVCaptureSession`)
- Bird sighting capture from photo library (`UIImagePickerController`)
- Automatic GPS tagging of sightings via `CLLocationManager`
- Background offline upload queue — persists failed uploads across app restarts
- Interactive sighting map powered by SwiftUI MapKit
- Viewport bounding-box filtering — only loads sightings in current map view
- Sighting detail view with community annotations
- Species annotation form with behavior, age/plumage, and confidence fields
- Community leaderboard — top annotators ranked by annotation count
- On-device bird identification via CoreML + Vision framework
- Silent background model update — checks server version on launch, downloads if newer
- Profile tab with sign-out

**Backend (FastAPI)**
- JWT authentication — register and login endpoints
- Sighting upload — multipart photo upload with PostGIS geolocation storage
- Automatic thumbnail generation (400×400 JPEG) via Pillow
- Sighting list endpoint with PostGIS bounding box filter (`ST_Within`)
- Sighting detail endpoint with all annotations
- Annotation submission endpoint with species, behavior, confidence fields
- Leaderboard endpoint — top users by annotation count
- Model version endpoint — returns active model metadata
- Model download endpoint — returns presigned MinIO URL
- Model registration endpoint — called by ML pipeline on training completion
- Health check endpoint

**ML Pipeline**
- Automated data fetch from backend API
- Plurality-vote species label assignment per sighting
- EfficientNet-B0 fine-tuning with AdamW + CosineAnnealingLR
- CoreML export via `coremltools` with embedded class labels
- MinIO model upload and version registration
- CLI arguments for API URL, token, min-annotations threshold, epochs

**Infrastructure**
- Docker Compose stack: FastAPI + PostgreSQL/PostGIS + MinIO
- PostGIS spatial index on sightings table
- `init.sql` migration script
- `.env`-based configuration with sensible local defaults
