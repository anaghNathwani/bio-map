# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BirdMap is a citizen science iOS app for bird sighting collection, community annotation, and on-device ML bird identification. The repo has three components: an iOS SwiftUI app, a FastAPI Python backend, and a PyTorch ML training pipeline.

## Commands

### Backend
```bash
# Start all services (Postgres+PostGIS, MinIO, FastAPI)
cd birdmap && docker-compose up -d

# Run DB migrations
docker-compose exec api python -m alembic upgrade head

# Tail API logs
docker-compose logs -f api
```

### iOS
```bash
# Open Xcode project
open birdmap/ios/BirdMap/BirdMap.xcodeproj
```
Set `APIClient.baseURL` in `APIClient.swift` to your machine's LAN IP for simulator/device testing (e.g. `http://192.168.1.x:8000`).

Build and run via Xcode (⌘R). No separate Swift CLI build is used.

### ML Pipeline
```bash
cd birdmap/ml_pipeline
pip install -r requirements.txt
python train.py --min-annotations 50
```

## Architecture

### iOS App (`ios/BirdMap/BirdMap/`)

**Entry point:** `App/BirdMapApp.swift` → routes to `LoginView` or `ContentView` (TabView) based on `AppEnvironment.token`.

**State:** `AppEnvironment` is a single `@EnvironmentObject` holding auth token + username in `UserDefaults`, injected at the root.

**Networking:** `Networking/APIClient.swift` — singleton `APIClient.shared`. All HTTP uses `batteryEfficientSession` (`waitsForConnectivity=true`). Throws typed `APIError`. Multipart upload is built inline.

**Offline queue:** `Networking/UploadQueue.swift` — Swift `actor`. Failed uploads are persisted as JPEG paths in `caches/pending_uploads/` with file paths stored in `UserDefaults`. Flushed on app launch.

**ML:** `ML/BirdClassifier.swift` wraps a CoreML `VNCoreMLRequest` on a `.userInitiated` background queue. `ML/ModelManager.swift` checks `/model/version`, downloads a zip via presigned URL, unzips with ZIPFoundation, then invalidates the `BirdClassifier` model cache.

**Views:**
- `Views/Auth/LoginView.swift` — login + register in one form, toggled by `isRegistering`
- `Views/Camera/CameraView.swift` + `CameraViewModel.swift` — photo capture (live AVFoundation or library picker), AI inference, upload flow
- `Views/Map/SightingMapView.swift` — MapKit annotations with 600ms debounced bbox fetch on camera change
- `Views/Sighting/SightingDetailView.swift` — photo, AI suggestion, community annotations list
- `Views/Sighting/AnnotationView.swift` — species/behavior/confidence form
- `Views/Leaderboard/LeaderboardView.swift` — ranked annotators list

### Backend (`backend/app/`)

FastAPI app wired in `main.py`. Routes split by domain in `api/`: `auth.py`, `sightings.py`, `annotations.py`, `leaderboard.py`, `model.py`. Services in `services/`: `storage.py` (boto3 → MinIO), `auth.py` (JWT + bcrypt). ORM models in `models/` use SQLAlchemy + GeoAlchemy2 (PostGIS `GEOMETRY(POINT, 4326)`).

### ML Pipeline (`ml_pipeline/train.py`)

Single script: fetches labelled sightings from the API, plurality-votes species labels, fine-tunes EfficientNet-B0 (PyTorch), exports to `.mlpackage` via `coremltools`, zips and uploads to MinIO, then registers the new version via `POST /model/register`.

### Key data flows

- **Sighting upload:** `CameraViewModel.upload()` → `APIClient.uploadSighting()` → `POST /sightings` → MinIO (photo + thumbnail) + PostGIS insert. On failure, `UploadQueue` persists to disk and retries on next launch.
- **Model update:** App launch → `ModelManager.checkForUpdate()` → compare version → download zip → unzip to `Documents/BirdClassifier.mlpackage` → `BirdClassifier` picks it up on next inference.
- **Self-learning loop:** Annotations accumulate → `python train.py` → new model registered → app silently downloads on next launch.
