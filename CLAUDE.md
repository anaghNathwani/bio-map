# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BirdMap is a citizen science iOS app for bird sighting collection, community annotation, and ML bird identification (on-device for photos and — as of the on-device BirdNET work — audio too; the scheduled server job is only a fallback for recordings the device couldn't analyze). **Everything runs on free tiers with no credit card attached anywhere** — genuinely true again as of the Firestore-only media architecture below, not just an aspiration; see docs/DEPLOYMENT.md for the full reasoning and history.

Backend:
- **Firebase (Auth + Firestore) is the entire live app's backend — data *and* media.** No Firebase Storage (needs Blaze billing for any usage), no Supabase, no deployed server of any kind. Sighting photo/audio bytes are compressed client-side and embedded as a base64 data URI directly in the sighting's Firestore document (`FirebaseService.uploadImage`/`uploadAudio`); the on-device ML model is the same idea scaled up — too large for one document, so it's split into base64 chunk documents under `model_versions/{id}/chunks` and reassembled by `ModelManager`. This pattern (compress + base64-in-Firestore, skip Storage entirely) follows github.com/ishanvi-dekate/team-efficient-epp, a prior project that used it successfully at zero cost — see that repo's `Profile.jsx` (avatar upload) and `ChatBot.jsx` (`imageToBase64`).
- **FastAPI backend** (`backend/`, Supabase-Postgres-backed) is a **separate, self-contained legacy system** (its own Postgres-backed auth/sightings/annotations/leaderboard) the live app doesn't call at all anymore — kept and deployable on request, not because the app depends on it. Its optional Google Vision bird-ID proxy (`/vision/identify`, called from `APIClient.identifyImage`) is the one thing in the live app that would still use it if deployed; call sites already treat it as optional and degrade silently without it. No backend needs to be deployed for the live app to fully work.

The self-hosted ML pipeline (`ml_pipeline/`) reads/writes Firestore via the Admin SDK only — no Supabase, no boto3, no S3 client. `publish_model.py` chunks the model zip and writes it straight into Firestore.

**Company policy: fine-tune, don't train from scratch.** The photo model (Google AIY Birds V1), photo object detector (Apple's pre-converted YOLOv3-Tiny/COCO CoreML model), and audio model (Cornell's BirdNET) are all complete, pre-trained, ready-to-use models from vetted American organizations — as of this writing all four models (including moderation) still run exactly as released, but policy has moved from "nothing trained in-house" to **fine-tuning (and quantizing) these pretrained weights on community-annotation data**, funded by and triggered on annotation volume rather than run continuously. `ml_pipeline/check_training_trigger.py` (run every 20 min by `.github/workflows/live-poll.yml`'s `check-training-trigger` job) checks Firestore for 500 newly-processed annotations since the last training run and logs when the threshold is crossed — it does not yet trigger any actual training, since the training/publish scripts it would call (a moderation classifier, a combined detector+classifier model) are designed but not yet built. `ml_pipeline/convert_photo_model.py` / `convert_bird_detector_model.py` + `publish_model.py` still only convert/republish the current pretrained models to CoreML. See `docs/ML_PIPELINE.md`'s "Our in-house training policy" section for what's live versus planned (and for why conversion and publishing are separate scripts — `coremltools` and `firebase-admin` can't be installed in the same environment).

**The photo classifier runs on TensorFlowLiteSwift (CocoaPods), not CoreML/Vision.** CoreML conversion of the AIY Birds V1 SavedModel is broken — confirmed directly: a converted `.mlpackage` produces the same near-uniform, input-independent output for a black image, a white image, random noise, and any real photo (reproduced across coremltools 7.2/9.0 and TF 2.13.1/2.15.1, so not a version fluke). Raw TensorFlow inference on the same SavedModel is excellent (>90% confidence, correct species), and TFLite conversion of it reproduces those correct results — so `convert_photo_model.py` now exports `.tflite` instead, and `BirdClassifier.swift` runs it via `TensorFlowLiteSwift`, doing its own image preprocessing (resize/crop/normalize) and label lookup since TFLite has no Vision/ClassifierConfig equivalent. The photo object detector (Tier 2, YOLOv3-Tiny/COCO) is unaffected and still CoreML — only the classifier's conversion was broken. A copy of the classifier is bundled directly into the app install (`ML/Bundled/BundledBirdModel.tflite`) so photo ID works immediately, with the Firestore/Supabase-fallback path (below) used only for shipping updates without an app release.

**Audio ID runs on-device too (BirdNET V2.4 via TFLite).** `BirdNETClassifier.swift` runs Cornell's BirdNET (`ML/Bundled/BundledBirdNET.tflite`, 51.7 MB) the moment a recording stops, plus BirdNET's location/season meta-model (`BundledBirdNETLocation.tflite`, 14.8 MB) fed the real GPS fix — without that filter BirdNET names implausible species for noise (a white-noise clip returned a European woodpecker at 0.50 in California). Sound classes (human voice, dog, engine, crickets) are blanked in `BundledBirdNETLabels.json` (identified by scientific name == common name in BirdNET's label file). Confidence floor 0.2 with a GPS fix, 0.35 without. Sightings analyzed on-device carry `aiAnalyzedAt`, so `live_poll.py` skips them; it remains the fallback (GitHub runs it every few hours, not every 20 minutes). Verified against real recordings degraded to phone quality (cardinal 0.96, house finch 0.96, house sparrow 0.68).

**Multiple birds in one sighting:** BirdNET (audio) already scores every species independently per segment, so `live_poll.py` surfaces every species clearing a confidence bar, not just the top one. Photos get the same treatment via two layered tiers: `MultiBirdDetector.swift`'s on-device Vision saliency (Tier 1, always available, no model download) crops and classifies extra salient regions; `BirdDetector.swift` (Tier 2, optional) uses a real object-detection CoreML model for far more reliable region-finding when its model has been published. Both feed the same `AdditionalBirdsSection` review UI as audio. See `docs/ML_PIPELINE.md`'s "Multiple birds in one photo/recording" section for the full detail, including why converting a TF-Hub COCO detector ourselves didn't work and what we used instead.

## Commands

### iOS
```bash
# Build and run from Terminal (NOT by opening the .xcodeproj — see gotchas below)
cd birdmap/ios/BirdMap
# Uses CocoaPods (TensorFlowLiteSwift) alongside SPM — build the .xcworkspace,
# NOT the .xcodeproj directly, or the Pods integration won't be there.
xcodebuild -workspace BirdMap.xcworkspace -scheme BirdMap -destination 'id=<simulator-udid>' -configuration Debug build

# After any `xcodegen generate`, project.yml's postGenCommand re-runs
# `pod install` automatically (xcodegen wipes CocoaPods' project integration
# every regen) — no separate manual step needed, but if `pod install` itself
# fails, run it manually: LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install
```

### ML Pipeline (self-hosted, talks directly to Firestore/Storage via the Admin SDK)
```bash
cd birdmap/ml_pipeline

# convert_photo_model.py no longer needs a separate venv/coremltools now that
# it exports TFLite instead of CoreML (see above) — same venv as everything
# else. convert_bird_detector_model.py (the Tier-2 detector, still CoreML)
# still needs requirements-convert.txt's separate venv.
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python convert_photo_model.py --output ./output
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

**Networking:** `Networking/FirebaseService.swift` is the primary data layer — auth, sightings, annotations, leaderboard, and media all go through Firestore/Auth directly, no Storage: `uploadImage` resizes to a max 1600px dimension and re-encodes JPEG at 0.85 quality, `uploadAudio` uses the raw recording (capped at 30s client-side), and both return a `data:<mime>;base64,...` URI string that `createSighting` writes straight into the sighting document. `Networking/DataURI.swift` decodes that format back out for display (`SightingDetailView` uses it directly for photo/audio rather than `AsyncImage`/`AVPlayer`'s URL loading, which doesn't reliably fetch `data:` URLs). `Networking/APIClient.swift` proxies the optional Google Vision bird-ID call (dead without a deployed backend, call sites already tolerate that) and does Wikipedia bird-info lookups directly (not proxied).

**Offline queue:** `Networking/UploadQueue.swift` — Swift `actor`. Failed uploads are persisted as JPEG paths in `caches/pending_uploads/` with file paths stored in `UserDefaults`. Flushed on app launch.

**ML:** `ML/BirdClassifier.swift` wraps a CoreML `VNCoreMLRequest` on a `.userInitiated` background queue — on-device photo species classification. `ML/BirdDetector.swift` wraps a second CoreML model (Tier 2 multi-bird detection, optional) that localizes bird-shaped regions via `VNRecognizedObjectObservation`, with NMS already baked into the model's pipeline. `ML/MultiBirdDetector.swift` is the entry point CameraViewModel actually calls: it prefers `BirdDetector` when its model is available, falling back to on-device Vision saliency (`VNGenerateObjectnessBasedSaliencyImageRequest`, no model download needed) otherwise, then crops+classifies each region with `BirdClassifier`. `ML/ModelManager.swift` queries the `model_versions` Firestore collection for the active `"photo"` classifier and (independently) the active `"photo_detector"` model, and if the version changed, reads every doc in that version's `chunks` subcollection (ordered by `index`), base64-decodes each one independently and concatenates the raw bytes (chunk boundaries don't align to base64's 3-byte groups, so this can't be done on the concatenated base64 strings), then unzips the result and invalidates the relevant model's cache. Audio classification is server-side (BirdNET via `ml_pipeline/live_poll.py`, scheduled) — the app uploads the recording and listens for the sighting doc's `aiSpeciesSuggestion` (plus `aiSpeciesSuggestions` for additional species) to populate, within one poll interval rather than instantly.

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

Self-hosted Python scripts using only the Firebase Admin SDK (`firestore_client.py`) — no Supabase, no S3 client, nothing else:
- `convert_photo_model.py` — downloads Google's pre-trained AIY Birds V1 model (MobileNetV2, Apache 2.0) from TensorFlow Hub as-is, resolves common names via the iNaturalist taxonomy API, converts to `.mlpackage` via `coremltools`. Writes a local zip + manifest.json — no Firebase involved at all (needs its own venv, `requirements-convert.txt` — `coremltools` and `firebase-admin` can't coexist in one environment, see docs/ML_PIPELINE.md).
- `convert_bird_detector_model.py` — Tier 2 multi-bird photo detection model. Downloads Apple's own pre-converted CoreML object detector (YOLOv3-Tiny/COCO) directly — no TF/coremltools conversion, since that path was tried against TF Hub's official detector and confirmed not to work with current tooling (see docs/ML_PIPELINE.md). Verifies the download's structure, writes the same zip + manifest.json layout as the photo model (`mediaType: "photo_detector"`).
- `publish_model.py` — takes a local zip + manifest (from either convert script above), splits it into ~650KB base64 chunk documents under a new `model_versions/{id}/chunks` subcollection (Firestore's 1 MiB per-document cap rules out storing it in one doc), and registers the version doc itself (`chunkCount`, `totalBytes`, `isActive`, etc.) keyed by `manifest["mediaType"]`. Uses `requirements.txt`, no coremltools, no Storage SDK of any kind. No training anywhere in this pipeline — a one-time conversion/publish step per model, run again only to re-publish.
- `live_poll.py` — run once per invocation (scheduled by `.github/workflows/live-poll.yml` in production, free): BirdNET audio analysis (writes `aiSpeciesSuggestion`/`aiConfidence`, plus `aiSpeciesSuggestions` for any additional distinct species, onto audio sightings with none yet) and annotation moderation (writes `moderation`/`moderationScore` onto annotations still marked `moderation == "pending"`, using a local sentence-embedding model).

Full details: `docs/ML_PIPELINE.md`. Free/no-card architecture reasoning: `docs/DEPLOYMENT.md`.

### Web frontend (`web/`)

React + Vite + Tailwind v4 (with `shadcn/tailwind.css` tokens) marketing site and community map, separate from the iOS app.

- `App.jsx` — the `/map` route: Leaflet map reading live sightings from Firestore (`src/firebase.js`'s `fetchSightings`), with `FilterBar`/`SightingPopup` for interaction. This is the one functional (non-marketing) page.
- `pages/LandingPage.jsx` — the marketing homepage. Design conventions to preserve when touching it: no emoji as icons (use `lucide-react`, one consistent stroke weight), no gradient-clip text for emphasis (solid `text-teal-300` instead), no eyebrow/kicker labels above headings, features rendered as a hairline-divided list rather than a grid of identical icon+heading+text cards. `components/canvasui/` holds several bespoke WebGL effects (`DitheredObject`, `Glass`, `Liquid`, `ParticleReveal`, `Glitch`) — only `DitheredObject` is used on the landing page (the hero bird mark); the others are unused elsewhere and were deliberately left out to keep the page to one authored motion effect rather than stacking all of them.
- `pages/AIPage.jsx`, `CommunityPage.jsx`, `CitizenSciencePage.jsx`, `TermsPage.jsx` — static content pages sharing `StaticPage.css`. Keep their AI/model claims consistent with the ML Pipeline section above (no in-house training/fine-tuning, no retraining from community annotations) — these pages previously claimed the photo model was "fine-tuned on community-submitted sightings" with a "retraining pipeline," which was factually wrong and has been corrected.

### Key data flows

- **Sighting upload:** `CameraViewModel.upload()` / `AudioRecorderViewModel.upload()` → `FirebaseService.uploadImage/uploadAudio` (client-side compression, no Storage, no backend) → `createSighting` → Firestore, with the compressed media embedded as a base64 data URI field on the document itself. On failure, `UploadQueue` persists to disk and retries on next launch.
- **Model update:** App launch → `ModelManager.checkForUpdate()` → independently checks `model_versions` for `"photo"` (classifier, → `Documents/BirdClassifier.mlpackage`, picked up by `BirdClassifier`) and `"photo_detector"` (Tier 2 detector, → `Documents/BirdDetector.mlmodel`, picked up by `BirdDetector`) → downloads+unzips whichever changed. Neither model changes on its own — this only fires again if the relevant convert script + `publish_model.py` are re-run to ship an updated/fixed version, or (for the detector) the first time it's ever published at all.
- **AI review loop:** Prediction shown (on-device for photo, async via `live_poll.py` for audio, polled within one interval) → user taps Right/Wrong/Unsure → `AnnotationView` pre-filled accordingly → `FirebaseService.submitAnnotation()` writes to Firestore with `reviewOfAI` set and `moderation: "pending"`. This builds a community dataset but does not retrain any model.
- **Moderation loop:** New annotation written with `moderation: "pending"` → next `live_poll.py` run classifies it → `moderation`/`moderationScore` written back → flagged annotations are excluded from the plurality-voted "top species" shown on a sighting.
