# Changelog

All notable changes to BirdMap are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Planned for v1.1
- ZipFoundation integration to replace `Process`-based model unzip on iOS
- Species autocomplete via a curated species list endpoint
- Annotation offline queue (mirrors the sighting upload queue)
- Layer-freezing strategy in ML pipeline for small-dataset training runs
- Webhook-triggered retraining when annotation count crosses a threshold

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
