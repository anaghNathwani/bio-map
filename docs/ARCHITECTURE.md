# Architecture Overview

## System Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          iOS App (SwiftUI)                          │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────────┐ │
│  │ Camera   │  │  Map     │  │ Annotate │  │  Leaderboard       │ │
│  │ + GPS    │  │ (MapKit) │  │ View     │  │  View              │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────────────────────┘ │
│       │              │              │                                │
│  ┌────▼──────────────▼──────────────▼──────────────────────────┐   │
│  │                      APIClient (URLSession)                  │   │
│  └─────────────────────────────┬───────────────────────────────┘   │
│                                │                                    │
│  ┌─────────────────────────────▼───────────────────────────────┐   │
│  │  ML Layer: BirdClassifier (CoreML + Vision)                  │   │
│  │  ModelManager: version check → background download → unzip   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  UploadQueue (UserDefaults): offline-first sighting buffer   │   │
│  └─────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ HTTPS / REST
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       FastAPI Backend                               │
│                                                                     │
│  /auth        /sightings        /annotations   /model              │
│  register     POST (upload)     POST           /version            │
│  login        GET  (bbox)       GET            /download           │
│               GET  (detail)                    /register           │
│                                                                     │
│  ┌──────────────────────┐   ┌──────────────────────────────────┐   │
│  │  PostgreSQL + PostGIS│   │  MinIO (S3-compatible)           │   │
│  │  - users             │   │  birdmap-photos/                 │   │
│  │  - sightings         │   │    sightings/*.jpg               │   │
│  │  - annotations       │   │    thumbnails/*.jpg              │   │
│  │  - model_versions    │   │  birdmap-models/                 │   │
│  │                      │   │    models/*.mlpackage.zip        │   │
│  └──────────────────────┘   └──────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                               │
                               │  Fetch annotations via API
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     ML Training Pipeline (Python)                   │
│                                                                     │
│  1. fetch_training_data()  — pull labelled sightings from API      │
│  2. train()                — fine-tune EfficientNet-B0 (PyTorch)   │
│  3. export_coreml()        — convert to .mlpackage (coremltools)   │
│  4. upload_and_register()  — push to MinIO, register version in DB │
│                                                                     │
│  Triggered manually (or via cron / webhook in v1.2+)               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

### iOS App

| Component | Responsibility |
|---|---|
| `BirdMapApp` | App lifecycle, routes to login or main tabs based on stored token |
| `AppEnvironment` | Shared auth state (token, username) persisted in UserDefaults |
| `APIClient` | All HTTP via `batteryEfficientSession` (`waitsForConnectivity=true`, 60s timeout); multipart upload builder; JWT bearer header; typed `APIError` throws |
| `UploadQueue` | Actor; persists failed uploads as JPEG file paths in caches directory; flushes on app launch; deletes files after successful upload |
| `BirdClassifier` | Wraps CoreML model in `VNCoreMLRequest`; caches `VNCoreMLModel` per version; runs inference on dedicated `.userInitiated` background queue; returns top species + confidence |
| `ModelManager` | Checks `/model/version`; downloads zip via presigned URL; unzips via ZIPFoundation; deletes zip after extraction; invalidates both its own `MLModel` cache and `BirdClassifier` cache after update |
| `CameraView` / `LiveCameraVC` | AVFoundation camera session with `stopRunning()` in `viewWillDisappear`; `UIImagePickerController` for library; starts/stops GPS on appear/disappear |
| `CameraViewModel` | GPS active only when Report tab visible (`startLocationUpdates`/`stopLocationUpdates`); `kCLLocationAccuracyHundredMeters`, 50m `distanceFilter`; `saveImageToTemp()` writes JPEG to disk for offline queue |
| `SightingMapView` | MapKit `Map` with per-pin annotations; bbox-filtered fetch debounced 600ms via `Task.sleep` + cancellation |
| `SightingDetailView` | Photo, AI suggestion, all community annotations, annotate CTA |
| `AnnotationView` | Species + behavior + confidence form; POSTs to `/annotations` |
| `LeaderboardView` | Ranked list of top annotators with medal icons |

### Backend

| Module | Responsibility |
|---|---|
| `app/api/auth.py` | JWT-based register/login; bcrypt password hashing |
| `app/api/sightings.py` | Multipart photo upload, thumbnail generation, PostGIS point insert, bbox query |
| `app/api/annotations.py` | Create annotations; increments user `annotation_count` |
| `app/api/leaderboard.py` | Query users ordered by `annotation_count` |
| `app/api/model.py` | Serve current model version metadata + presigned download URL; accept registration from ML pipeline |
| `app/services/storage.py` | S3 put/get via boto3; thumbnail resize via Pillow |
| `app/services/auth.py` | JWT encode/decode; password hash/verify |
| `app/models/` | SQLAlchemy ORM models with GeoAlchemy2 for spatial data |

### ML Pipeline

| Step | Detail |
|---|---|
| Data fetch | GET `/sightings?limit=5000` → GET `/sightings/{id}` for each → plurality-vote species label |
| Filtering | Only species with ≥ `--min-annotations` samples are included |
| Training | EfficientNet-B0 (ImageNet pretrained), final classifier layer replaced, AdamW + CosineAnnealingLR |
| Export | `torch.jit.trace` → `coremltools.convert()` with `ClassifierConfig` (embeds class labels) |
| Upload | Zips `.mlpackage` directory → puts to MinIO |
| Register | POST `/model/register` with version, s3_key, accuracy, class list |

---

## Data Flow: Sighting Submission

```
User taps "Submit"
    │
    ├─ CameraViewModel.upload()
    │       │
    │       ├─ Compress JPEG (85% quality)
    │       ├─ Read CLLocation from locationManager
    │       └─ APIClient.uploadSighting(imageData, lat, lng, notes)
    │               │
    │               └─ POST /sightings (multipart/form-data)
    │                       │
    │                       ├─ storage.upload_photo()
    │                       │       ├─ PUT photo → MinIO birdmap-photos/sightings/
    │                       │       └─ PUT thumbnail → MinIO birdmap-photos/thumbnails/
    │                       │
    │                       └─ INSERT INTO sightings (location=ST_MakePoint(lng, lat))
    │
    └─ On network failure:
            CameraViewModel.saveImageToTemp()    → JPEG written to caches/pending_uploads/
            UploadQueue.enqueue(PendingUpload)   → file path persisted to UserDefaults
            UploadQueue.flushIfNeeded()          → retried on next launch
            (image file deleted after successful upload)
```

## Data Flow: Self-Learning Loop

```
Annotations accumulate in DB
        │
        ▼
python train.py --min-annotations 50
        │
        ├─ fetch_training_data() → GET /sightings → GET /sightings/{id}
        │       → plurality-vote species per sighting
        │
        ├─ train() → EfficientNet-B0 fine-tune, best val-acc checkpoint
        │
        ├─ export_coreml() → BirdClassifier.mlpackage
        │
        ├─ zip + PUT → MinIO birdmap-models/
        │
        └─ POST /model/register → sets new version as active in DB
                │
                ▼
        App launch: ModelManager.checkForUpdate()
                │
                ├─ GET /model/version → compare with stored version string
                ├─ GET /model/download → presigned URL
                ├─ URLSession.download(from: url) → temp file
                ├─ unzip → Documents/BirdClassifier.mlpackage
                └─ Store new version string in UserDefaults
                        │
                        ▼
                BirdClassifier uses new model on next inference call
```

---

## Database Schema

```sql
users
  id UUID PK
  email VARCHAR(255) UNIQUE
  username VARCHAR(80) UNIQUE
  hashed_password VARCHAR(255)
  annotation_count INTEGER DEFAULT 0
  created_at TIMESTAMP

sightings
  id UUID PK
  user_id UUID FK → users.id
  photo_url VARCHAR(1024)
  thumbnail_url VARCHAR(1024)
  location GEOMETRY(POINT, 4326)   ← PostGIS spatial index
  latitude DOUBLE PRECISION
  longitude DOUBLE PRECISION
  notes TEXT
  ai_species_suggestion VARCHAR(255)
  ai_confidence DOUBLE PRECISION
  created_at TIMESTAMP

annotations
  id UUID PK
  sighting_id UUID FK → sightings.id ON DELETE CASCADE
  user_id UUID FK → users.id
  species VARCHAR(255)
  confidence DOUBLE PRECISION      ← annotator self-rating 0.0–1.0
  behavior VARCHAR(255)
  age_plumage VARCHAR(100)
  created_at TIMESTAMP

model_versions
  id SERIAL PK
  version VARCHAR(50) UNIQUE       ← e.g. "20240601_143022"
  s3_key VARCHAR(1024)
  num_classes INTEGER
  accuracy DOUBLE PRECISION
  is_active BOOLEAN DEFAULT TRUE
  created_at TIMESTAMP
```

---

## Technology Choices & Rationale

| Decision | Alternative considered | Reason chosen |
|---|---|---|
| **FastAPI** | Django REST, Flask | Async-native, automatic OpenAPI docs, Pydantic validation |
| **PostGIS** | Plain PostgreSQL, MongoDB geospatial | Industry standard for geospatial queries; ST_Within, ST_MakeEnvelope built-in |
| **GeoAlchemy2** | Raw SQL spatial queries | Type-safe ORM integration with PostGIS |
| **MinIO** | AWS S3, local disk | S3-compatible; self-hostable; no cloud vendor lock-in for development |
| **EfficientNet-B0** | ResNet-50, MobileNetV3 | Best accuracy/size tradeoff; small enough to run on Mac for training |
| **coremltools** | ONNX → CoreML converter | First-party Apple tool; best support for iOS 16+ features |
| **SwiftUI** | UIKit | Declarative, faster iteration, native on all Apple platforms |
| **MapKit** | Google Maps SDK, Mapbox | No API key required; ships with iOS; native performance |
| **AVFoundation** | PhotosUI `PhotosPicker` | Full camera session control (exposure, focus, resolution) |
| **UserDefaults for UploadQueue** | Core Data, SQLite | Simple enough for a list of pending uploads; survives app kill |
