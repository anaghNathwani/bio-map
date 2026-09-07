# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BirdMap is a citizen science iOS app for bird sighting collection, community annotation, and ML bird identification (on-device for photos, server-side for audio). It started from an **everything runs on free tiers with no credit card attached anywhere** constraint — see docs/DEPLOYMENT.md for the full reasoning — but that constraint was explicitly lifted for sighting media specifically (below), since no backend was ever actually deployed and the project owner decided billing was an acceptable tradeoff for getting reporting working.

Backends:
- **Firebase** (Auth, Firestore, and now **Storage**) is the live app's data store *and* media store — sightings, annotations, users, leaderboard, and sighting photo/audio blobs. Storage requires the Blaze billing plan; that's been enabled for this project specifically so `FirebaseService.uploadImage`/`uploadAudio` can upload directly via the FirebaseStorage SDK, no backend involved. `storage.rules` is active (owner-write, any-logged-in-user-read).
- **FastAPI backend** (`backend/`, Supabase-Postgres-backed) is now a **separate, self-contained legacy system** (its own Postgres-backed auth/sightings/annotations/leaderboard) that the live app doesn't call for media anymore — kept and deployable on request, not because the app depends on it. Its optional Google Vision bird-ID proxy (`/vision/identify`, called from `APIClient.identifyImage`) is the one thing in the live app that would still use it if deployed; call sites already treat it as optional and degrade silently without it.

The self-hosted ML pipeline (`ml_pipeline/`) reads/writes Firestore via the Admin SDK and Supabase Storage via boto3 (S3-compatible).

**Company policy: fine-tune, don't train from scratch.** The photo model (Google AIY Birds V1), photo object detector (Apple's pre-converted YOLOv3-Tiny/COCO CoreML model), and audio model (Cornell's BirdNET) are all complete, pre-trained, ready-to-use models from vetted American organizations — as of this writing all four models (including moderation) still run exactly as released, but policy has moved from "nothing trained in-house" to **fine-tuning (and quantizing) these pretrained weights on community-annotation data**, funded by and triggered on annotation volume rather than run continuously. `ml_pipeline/check_training_trigger.py` (run every 20 min by `.github/workflows/live-poll.yml`'s `check-training-trigger` job) checks Firestore for 500 newly-processed annotations since the last training run and logs when the threshold is crossed — it does not yet trigger any actual training, since the training/publish scripts it would call (a moderation classifier, a combined detector+classifier model) are designed but not yet built. `ml_pipeline/convert_photo_model.py` / `convert_bird_detector_model.py` + `publish_model.py` still only convert/republish the current pretrained models to CoreML. See `docs/ML_PIPELINE.md`'s "Our in-house training policy" section for what's live versus planned (and for why conversion and publishing are separate scripts — `coremltools` and `firebase-admin` can't be installed in the same environment).

**Note: no Supabase project has actually been provisioned for this app.** `backend/.env` only has local Docker-Compose dev placeholders; there's no `backend/.env.supabase`. This means `publish_model.py` can't work — so `model_versions` in Firestore is empty and `ModelManager` has nothing to download yet — until `provision-supabase.sh` is run against a real Supabase account, then `convert_photo_model.py` + `publish_model.py`. (Sighting photo/audio uploads no longer depend on Supabase/the backend at all — see above — so this gap is now scoped to model publishing only.)

**Multiple birds in one sighting:** BirdNET (audio) already scores every species independently per segment, so `live_poll.py` surfaces every species clearing a confidence bar, not just the top one. Photos get the same treatment via two layered tiers: `MultiBirdDetector.swift`'s on-device Vision saliency (Tier 1, always available, no model download) crops and classifies extra salient regions; `BirdDetector.swift` (Tier 2, optional) uses a real object-detection CoreML model for far more reliable region-finding when its model has been published. Both feed the same `AdditionalBirdsSection` review UI as audio. See `docs/ML_PIPELINE.md`'s "Multiple birds in one photo/recording" section for the full detail, including why converting a TF-Hub COCO detector ourselves didn't work and what we used instead.

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

# One-time photo *detector* publish (Tier 2 multi-bird photo detection) — no
# TF/coremltools conversion involved, just downloads + verifies Apple's own
# pre-converted CoreML object detector; see docs/ML_PIPELINE.md for why:
source .venv-convert/bin/activate
python convert_bird_detector_model.py --output ./output_detector
deactivate
source .venv/bin/activate
python publish_model.py --input ./output_detector

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

# Production, pick one compute target (same Supabase data layer either way,
# shared via provision-supabase.sh -> backend/.env.supabase):
./deploy.sh /path/to/firebase-service-account.json                      # Render — needs a card, confirmed live
./deploy-gcp.sh <gcp-project-id> /path/to/firebase-service-account.json # Cloud Run — needs GCP billing enabled
./deploy-selfhost.sh                                                    # runs ON the spare machine, not here — needs backend/.env.supabase copied over
# See docs/DEPLOYMENT.md
```
The media upload broker (`app/api/media.py`) is load-bearing — every real photo/audio upload from the app goes through it. The rest (`auth.py`, `sightings.py`, `annotations.py`, `leaderboard.py`, `model.py`) is a separate, independent Postgres-backed system the live app doesn't call.

### Web (`web/`)
```bash
cd birdmap/web
npm run dev      # Vite dev server
npm run build    # production build to dist/
```
Reads `sightings` directly from Firestore client-side (`src/firebase.js`) — no backend involved. Not the same codebase as the iOS app; see Architecture below.

## Architecture

### iOS App (`ios/BirdMap/BirdMap/`)

**Entry point:** `App/BirdMapApp.swift` → routes to `LoginView` or `ContentView` (TabView) based on Firebase Auth state (`AppEnvironment`).

**State:** `AppEnvironment` is a single `@EnvironmentObject` holding the Firebase `user`/`username`, injected at the root.

**Networking:** `Networking/FirebaseService.swift` is the primary data layer — auth, sightings, annotations, leaderboard, and now media all go through Firebase directly: `uploadImage`/`uploadAudio` upload straight to Firebase Storage (`sightings/{id}/photo.jpg` / `sightings/{id}/{filename}`) via the FirebaseStorage SDK and return the resulting `downloadURL()`. `Networking/APIClient.swift` proxies the optional Google Vision bird-ID call (dead without a deployed backend, call sites already tolerate that) and does Wikipedia bird-info lookups directly (not proxied).

**Offline queue:** `Networking/UploadQueue.swift` — Swift `actor`. Failed uploads are persisted as JPEG paths in `caches/pending_uploads/` with file paths stored in `UserDefaults`. Flushed on app launch.

**ML:** `ML/BirdClassifier.swift` wraps a CoreML `VNCoreMLRequest` on a `.userInitiated` background queue — on-device photo species classification. `ML/BirdDetector.swift` wraps a second CoreML model (Tier 2 multi-bird detection, optional) that localizes bird-shaped regions via `VNRecognizedObjectObservation`, with NMS already baked into the model's pipeline. `ML/MultiBirdDetector.swift` is the entry point CameraViewModel actually calls: it prefers `BirdDetector` when its model is available, falling back to on-device Vision saliency (`VNGenerateObjectnessBasedSaliencyImageRequest`, no model download needed) otherwise, then crops+classifies each region with `BirdClassifier`. `ML/ModelManager.swift` queries the `model_versions` Firestore collection for the active `"photo"` classifier and (independently) the active `"photo_detector"` model, downloading/unzipping either from its `downloadURL` (public Supabase Storage URLs — no Firebase Storage, no auth needed) if its version changed, then invalidating the relevant model's cache. Audio classification is server-side (BirdNET via `ml_pipeline/live_poll.py`, scheduled) — the app uploads the recording and listens for the sighting doc's `aiSpeciesSuggestion` (plus `aiSpeciesSuggestions` for additional species) to populate, within one poll interval rather than instantly.

**Views:**
- `Views/Auth/LoginView.swift` — login + register in one form, toggled by `isRegistering`
- `Views/Camera/CameraView.swift` + `CameraViewModel.swift` — photo capture (live AVFoundation or library picker), on-device AI inference (species + multi-bird detection), upload flow, post-upload AI review (Right/Wrong/Unsure)
- `Views/Camera/AIPredictionCard.swift` — shared prediction + reference-photo + review card for the primary suggestion, used by both photo and audio flows
- `Views/Camera/AdditionalBirdsSection.swift` — shared review list for extra detected species beyond the primary one (audio's BirdNET secondary matches, photo's Tier 1/2 additional regions); each row submits its own annotation directly
- `Views/Camera/AudioRecorderView.swift` + `AudioRecorderViewModel.swift` — recording, upload, "analyzing" wait state, then the same AI review flow once BirdNET's server-side result lands
- `Views/Map/SightingMapView.swift` — MapKit annotations with 600ms debounced bbox fetch on camera change
- `Views/Sighting/SightingDetailView.swift` — photo/audio, AI suggestion(s) including any additional detected species, community annotations list (with a "flagged" badge for moderated annotations)
- `Views/Sighting/AnnotationView.swift` — species/behavior/confidence form; can be pre-filled from an AI review verdict
- `Views/Leaderboard/LeaderboardView.swift` — ranked annotators list

### ML Pipeline (`ml_pipeline/`)

Self-hosted Python scripts using the Firebase Admin SDK (`firestore_client.py`) for Firestore, and boto3 for Supabase Storage:
- `convert_photo_model.py` — downloads Google's pre-trained AIY Birds V1 model (MobileNetV2, Apache 2.0) from TensorFlow Hub as-is, resolves common names via the iNaturalist taxonomy API, converts to `.mlpackage` via `coremltools`. Writes a local zip + manifest.json — no Firebase or Supabase involved (needs its own venv, `requirements-convert.txt` — `coremltools` and `firebase-admin` can't coexist in one environment, see docs/ML_PIPELINE.md).
- `convert_bird_detector_model.py` — Tier 2 multi-bird photo detection model. Downloads Apple's own pre-converted CoreML object detector (YOLOv3-Tiny/COCO) directly — no TF/coremltools conversion, since that path was tried against TF Hub's official detector and confirmed not to work with current tooling (see docs/ML_PIPELINE.md). Verifies the download's structure, writes the same zip + manifest.json layout as the photo model (`mediaType: "photo_detector"`).
- `publish_model.py` — takes a local zip + manifest (from either convert script above), uploads to Supabase Storage (boto3, S3-compatible), registers the new version in Firestore `model_versions` keyed by `manifest["mediaType"]`. Uses `requirements.txt`, no coremltools. No training anywhere in this pipeline — a one-time conversion/publish step per model, run again only to re-publish.
- `live_poll.py` — run once per invocation (scheduled by `.github/workflows/live-poll.yml` in production, free): BirdNET audio analysis (writes `aiSpeciesSuggestion`/`aiConfidence`, plus `aiSpeciesSuggestions` for any additional distinct species, onto audio sightings with none yet) and annotation moderation (writes `moderation`/`moderationScore` onto annotations still marked `moderation == "pending"`, using a local sentence-embedding model).

Full details: `docs/ML_PIPELINE.md`. Free/no-card architecture reasoning: `docs/DEPLOYMENT.md`.

### Web frontend (`web/`)

React + Vite + Tailwind v4 (with `shadcn/tailwind.css` tokens) marketing site and community map, separate from the iOS app.

- `App.jsx` — the `/map` route: Leaflet map reading live sightings from Firestore (`src/firebase.js`'s `fetchSightings`), with `FilterBar`/`SightingPopup` for interaction. This is the one functional (non-marketing) page.
- `pages/LandingPage.jsx` — the marketing homepage. Design conventions to preserve when touching it: no emoji as icons (use `lucide-react`, one consistent stroke weight), no gradient-clip text for emphasis (solid `text-teal-300` instead), no eyebrow/kicker labels above headings, features rendered as a hairline-divided list rather than a grid of identical icon+heading+text cards. `components/canvasui/` holds several bespoke WebGL effects (`DitheredObject`, `Glass`, `Liquid`, `ParticleReveal`, `Glitch`) — only `DitheredObject` is used on the landing page (the hero bird mark); the others are unused elsewhere and were deliberately left out to keep the page to one authored motion effect rather than stacking all of them.
- `pages/AIPage.jsx`, `CommunityPage.jsx`, `CitizenSciencePage.jsx`, `TermsPage.jsx` — static content pages sharing `StaticPage.css`. Keep their AI/model claims consistent with the ML Pipeline section above (no in-house training/fine-tuning, no retraining from community annotations) — these pages previously claimed the photo model was "fine-tuned on community-submitted sightings" with a "retraining pipeline," which was factually wrong and has been corrected.

### Key data flows

- **Sighting upload:** `CameraViewModel.upload()` / `AudioRecorderViewModel.upload()` → `FirebaseService.uploadImage/uploadAudio` (direct FirebaseStorage SDK upload, no backend) → Firebase Storage, then `createSighting` → Firestore, with the returned download URL. On failure, `UploadQueue` persists to disk and retries on next launch.
- **Model update:** App launch → `ModelManager.checkForUpdate()` → independently checks `model_versions` for `"photo"` (classifier, → `Documents/BirdClassifier.mlpackage`, picked up by `BirdClassifier`) and `"photo_detector"` (Tier 2 detector, → `Documents/BirdDetector.mlmodel`, picked up by `BirdDetector`) → downloads+unzips whichever changed. Neither model changes on its own — this only fires again if the relevant convert script + `publish_model.py` are re-run to ship an updated/fixed version, or (for the detector) the first time it's ever published at all.
- **AI review loop:** Prediction shown (on-device for photo, async via `live_poll.py` for audio, polled within one interval) → user taps Right/Wrong/Unsure → `AnnotationView` pre-filled accordingly → `FirebaseService.submitAnnotation()` writes to Firestore with `reviewOfAI` set and `moderation: "pending"`. This builds a community dataset but does not retrain any model.
- **Moderation loop:** New annotation written with `moderation: "pending"` → next `live_poll.py` run classifies it → `moderation`/`moderationScore` written back → flagged annotations are excluded from the plurality-voted "top species" shown on a sighting.
