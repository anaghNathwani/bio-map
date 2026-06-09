# BirdMap

Citizen science iOS app for bird sighting collection, community annotation, and on-device ML bird identification. Modeled after the Stanford mosquito-tracking citizen science concept.

## How it works

1. **Capture** — Users photograph a bird; GPS coordinates are automatically attached.
2. **Upload** — Photo + geolocation are sent to the backend and stored in PostGIS-enabled PostgreSQL.
3. **Annotate** — Other users label sightings (species, confidence, behavior) to build a training dataset.
4. **Retrain** — When enough new annotations accumulate, a Python pipeline retrains an EfficientNet classifier and exports it to CoreML format.
5. **Update** — The app checks a model-version endpoint and silently downloads the new `.mlpackage` in the background.
6. **Identify** — On-device CoreML inference gives instant bird ID suggestions, even offline.

## Tech stack

| Layer | Technology |
|---|---|
| iOS | SwiftUI, MapKit, AVFoundation, CoreLocation, CoreML + Vision |
| Backend API | FastAPI (Python 3.11) |
| Database | PostgreSQL 15 + PostGIS |
| Object storage | MinIO (S3-compatible) |
| ML training | PyTorch + `coremltools` export |
| Infrastructure | Docker Compose |

## Quick start

### Prerequisites
- Docker + Docker Compose
- Xcode 15+
- Python 3.11 (for local ML work)

### 1. Start backend services

```bash
cd birdmap
cp backend/.env.example backend/.env   # fill in secrets
docker-compose up -d
```

This starts:
- PostgreSQL + PostGIS on port 5432
- MinIO on ports 9000/9001
- FastAPI on port 8000

### 2. Run database migrations

```bash
docker-compose exec api python -m alembic upgrade head
```

### 3. Open iOS app

```
open ios/BirdMap/BirdMap.xcodeproj
```

Set `APIClient.baseURL` in `APIClient.swift` to your machine's LAN IP (e.g. `http://192.168.1.x:8000`) for simulator/device testing.

Build and run on a real device or simulator.

### 4. Trigger model retraining (manual)

```bash
cd ml_pipeline
pip install -r requirements.txt
python train.py --min-annotations 50
```

The script fetches annotated sightings from the API, trains, exports to CoreML, and uploads the new model — the app picks it up automatically on next launch.

## API overview

| Method | Path | Description |
|---|---|---|
| POST | `/auth/register` | Register user |
| POST | `/auth/login` | Get JWT |
| POST | `/sightings` | Upload sighting (multipart) |
| GET | `/sightings` | List sightings (bbox filter) |
| GET | `/sightings/{id}` | Sighting detail |
| POST | `/sightings/{id}/annotations` | Submit annotation |
| GET | `/leaderboard` | Top annotators |
| GET | `/model/version` | Latest model metadata |
| GET | `/model/download` | Download `.mlpackage` zip |

## Biosphere mapping

All sightings are stored with PostGIS geometry. Use the `/sightings` endpoint with `bbox` query params to pull heatmap data for any region. The backend exposes a GeoJSON endpoint suitable for feeding into QGIS, Mapbox, or any mapping tool.
