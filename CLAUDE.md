# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BirdMap is a citizen science iOS app for bird sighting collection, community annotation, and ML bird identification (on-device for photos, server-side for audio). **Everything runs on free tiers with no credit card attached anywhere** — this shaped several architecture decisions below; see docs/DEPLOYMENT.md for the full reasoning.

Two backends, each with a real job:
- **Firebase** (Auth, Firestore) is the live app's data store — sightings, annotations, users, leaderboard. Unaffected by any billing requirement; only Firebase *Storage* needs a paid plan, which is why Storage isn't used at all (see below).
- **FastAPI backend** (`backend/`, deployed to Render, backed by Supabase Postgres) does two independent things: (1) a **media upload broker** — verifies the live app's Firebase ID tokens and proxies photo/audio uploads to Supabase Storage (free, no card, unlike Firebase Storage), used by every real user of the app; (2) a **separate, self-contained legacy system** (its own Postgres-backed auth/sightings/annotations/leaderboard) that the live app doesn't call at all — kept and deployable on request, not because the app depends on it.

The self-hosted ML pipeline (`ml_pipeline/`) reads/writes Firestore via the Admin SDK and Supabase Storage via boto3 (S3-compatible).

**No models are trained or fine-tuned in-house.** Both the photo model (Google AIY Birds V1) and audio model (Cornell's BirdNET) are complete, pre-trained, ready-to-use models from vetted American organizations, used exactly as released. `ml_pipeline/convert_photo_model.py` + `publish_model.py` only convert/republish the photo model to CoreML — they do not train anything. See `docs/ML_PIPELINE.md` for why (and for why that's two scripts, not one — `coremltools` and `firebase-admin` can't be installed in the same environment).

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

# One-time photo model publish — TWO separate venvs, not one (coremltools and
# firebase-admin require mutually incompatible protobuf ranges, confirmed —
# see docs/ML_PIPELINE.md):
python3 -m venv .venv-convert && source .venv-convert/bin/activate
pip install -r requirements-convert.txt
python convert_photo_model.py --output ./output
deactivate

python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python publish_model.py --input ./output

# Live audio ID (BirdNET) + annotation moderation — polls once and exits;
# scheduled by .github/workflows/live-poll.yml in production (free, no
# always-on machine needed), or run manually/on a cron for local testing:
python live_poll.py
```
Needs Firebase Admin credentials: `--service-account <path>`, `GOOGLE_APPLICATION_CREDENTIALS`, or Application Default Credentials (`gcloud auth application-default login`). See `docs/ML_PIPELINE.md`.

### Backend
```bash
# Local dev (Postgres + MinIO via Docker Compose)
cd birdmap && docker-compose up -d

# Production: ./deploy.sh /path/to/firebase-service-account.json
# (Render + Supabase, see docs/DEPLOYMENT.md)
```
The media upload broker (`app/api/media.py`) is load-bearing — every real photo/audio upload from the app goes through it. The rest (`auth.py`, `sightings.py`, `annotations.py`, `leaderboard.py`, `model.py`) is a separate, independent Postgres-backed system the live app doesn't call.

## Architecture

### iOS App (`ios/BirdMap/BirdMap/`)

**Entry point:** `App/BirdMapApp.swift` → routes to `LoginView` or `ContentView` (TabView) based on Firebase Auth state (`AppEnvironment`).

**State:** `AppEnvironment` is a single `@EnvironmentObject` holding the Firebase `user`/`username`, injected at the root.

**Networking:** `Networking/FirebaseService.swift` is the primary data layer — auth, sightings, annotations, and leaderboard reads/writes go through Firestore/Auth directly, **except the media blob itself**: `uploadImage`/`uploadAudio` fetch a Firebase ID token and call `APIClient.shared.uploadPhoto`/`uploadAudio`, which POST to the backend's media broker (`/media/sightings/{id}/photo|audio`) — that's what actually lands the bytes in Supabase Storage. `Networking/APIClient.swift` also proxies the optional Google Vision bird-ID call and does Wikipedia bird-info lookups directly (not proxied).

**Offline queue:** `Networking/UploadQueue.swift` — Swift `actor`. Failed uploads are persisted as JPEG paths in `caches/pending_uploads/` with file paths stored in `UserDefaults`. Flushed on app launch.

**ML:** `ML/BirdClassifier.swift` wraps a CoreML `VNCoreMLRequest` on a `.userInitiated` background queue — on-device photo classification. `ML/ModelManager.swift` queries the `model_versions` Firestore collection for the active photo model and downloads the `.mlpackage.zip` from its `downloadURL` (a public Supabase Storage URL — no Firebase Storage, no auth needed to fetch it) if the version changed, unzips with ZIPFoundation, then invalidates the `BirdClassifier` model cache. Audio classification is server-side (BirdNET via `ml_pipeline/live_poll.py`, scheduled) — the app uploads the recording and listens for the sighting doc's `aiSpeciesSuggestion` to populate, polled in within one interval rather than instantly.

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

Self-hosted Python scripts using the Firebase Admin SDK (`firestore_client.py`) for Firestore, and boto3 for Supabase Storage:
- `convert_photo_model.py` — downloads Google's pre-trained AIY Birds V1 model (MobileNetV2, Apache 2.0) from TensorFlow Hub as-is, resolves common names via the iNaturalist taxonomy API, converts to `.mlpackage` via `coremltools`. Writes a local zip + manifest.json — no Firebase or Supabase involved (needs its own venv, `requirements-convert.txt` — `coremltools` and `firebase-admin` can't coexist in one environment, see docs/ML_PIPELINE.md).
- `publish_model.py` — takes that local zip + manifest, uploads to Supabase Storage (boto3, S3-compatible), registers the new version in Firestore `model_versions`. Uses `requirements.txt`, no coremltools. No training anywhere in this pair — a one-time conversion/publish step, run again only to re-publish.
- `live_poll.py` — run once per invocation (scheduled by `.github/workflows/live-poll.yml` in production, free): BirdNET audio analysis (writes `aiSpeciesSuggestion`/`aiConfidence` onto audio sightings with none yet) and annotation moderation (writes `moderation`/`moderationScore` onto annotations still marked `moderation == "pending"`, using a local sentence-embedding model).

Full details: `docs/ML_PIPELINE.md`. Free/no-card architecture reasoning: `docs/DEPLOYMENT.md`.

### Key data flows

- **Sighting upload:** `CameraViewModel.upload()` / `AudioRecorderViewModel.upload()` → `FirebaseService.uploadImage/uploadAudio` (fetches a Firebase ID token, POSTs to the backend's `/media` broker) → Supabase Storage, then `createSighting` → Firestore, with the returned public URL. On failure, `UploadQueue` persists to disk and retries on next launch.
- **Model update:** App launch → `ModelManager.checkForUpdate()` → query `model_versions` → download zip from its `downloadURL` if version changed → unzip to `Documents/BirdClassifier.mlpackage` → `BirdClassifier` picks it up on next inference. The model itself never changes on its own — this only fires again if `convert_photo_model.py` + `publish_model.py` are re-run to ship an updated/fixed version.
- **AI review loop:** Prediction shown (on-device for photo, async via `live_poll.py` for audio, polled within one interval) → user taps Right/Wrong/Unsure → `AnnotationView` pre-filled accordingly → `FirebaseService.submitAnnotation()` writes to Firestore with `reviewOfAI` set and `moderation: "pending"`. This builds a community dataset but does not retrain any model.
- **Moderation loop:** New annotation written with `moderation: "pending"` → next `live_poll.py` run classifies it → `moderation`/`moderationScore` written back → flagged annotations are excluded from the plurality-voted "top species" shown on a sighting.
