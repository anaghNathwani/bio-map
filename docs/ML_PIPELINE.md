# ML Pipeline

## Overview

BirdMap ships four models. **None of them are trained or fine-tuned in-house** — all are used exactly as released by their publisher, all sourced from vetted American organizations (no Chinese-origin models or weights):

| Model | Publisher | Modality | Runs | Fine-tuned by us? |
|---|---|---|---|---|
| Bird species ID | Google (AIY Projects), Apache 2.0 | Photo | On-device (CoreML) | No — used as-is |
| Multi-bird photo detector (Tier 2) | Apple (pre-converted CoreML catalog); YOLOv3-Tiny trained on COCO by Redmon/Farhadi, U. Washington | Photo | On-device (CoreML) | No — used as-is; optional, see below |
| Bird call ID | Cornell Lab of Ornithology (BirdNET) | Audio | Server-side (`birdnetlib`) | No — used as-is |
| Annotation moderation | `sentence-transformers` (`all-MiniLM-L6-v2`) | Text | Server-side | No — zero-shot classification via exemplar phrases, no training |

The citizen-science feedback loop:

1. User uploads a photo or recording → the relevant model predicts a species (or, for photos/audio with more than one bird, several) and shows a reference photo per species.
2. User confirms (Right), corrects (Wrong), or says Unsure for each suggestion, optionally adding behavior/plumage details, which becomes an annotation in Firestore.
3. A moderation pass classifies each new annotation as genuine or a "shitpost" (silly/joke content).
4. Annotations accumulate as a community dataset (plurality-voted "top species" shown per sighting, leaderboard, etc.) — but **do not retrain any model**. Recognition quality comes entirely from the upstream publisher's own pretrained model(s).

**Firestore** (`birdmap-citizenscience` project) is the database for all of this. **Blob storage (photos/audio/model files) is Supabase Storage, not Firebase Storage** — Firebase Storage now requires a linked billing account (Blaze) for any usage, and the whole point of this pipeline's hosting is to stay free with no card required anywhere; see `docs/DEPLOYMENT.md`. Uploads go through the `backend/` FastAPI service (`app/api/media.py`), which verifies the app's Firebase ID token before writing to Supabase Storage on the user's behalf; downloads are direct public Supabase URLs, no backend involved.

---

## Photo model: Google AIY Birds V1

| Property | Value |
|---|---|
| Publisher | Google (AIY Projects) |
| Architecture | MobileNetV2 |
| Training dataset | iNaturalist 2017 Competition dataset (curated by Visipedia) |
| Classes | 964 bird species |
| License | Apache 2.0 |
| Input | 224 × 224 × 3 RGB, scaled to [0, 1] |
| Export format | Apple CoreML `.mlpackage` |
| Minimum iOS target | iOS 16 |
| Runs | On-device, via `BirdClassifier.swift` (Vision + CoreML), unchanged from before |
| Source | [tfhub.dev/google/aiy/vision/classifier/birds_V1](https://tfhub.dev/google/aiy/vision/classifier/birds_V1/1) |

This is a complete, ready-to-use classifier — **we do not train or fine-tune it**. `ml_pipeline/convert_photo_model.py` (conversion) and `publish_model.py` (Supabase Storage + Firestore publish) only *convert and republish* it:

1. Downloads the SavedModel and official labelmap from TensorFlow Hub (Google's own hosting). The SavedModel exposes two signatures for the same graph (`image_classifier`, `default`); we load it with `tf.saved_model.load()` and hand coremltools the `image_classifier` concrete function specifically, since its TF2 loader can't handle a SavedModel with more than one. Its real input placeholder is named `hub_input/images` (not `images`, despite that being the signature-level name).
2. Resolves each scientific name (e.g. `Cyanocitta cristata`) to a common name (`Blue Jay`) via the iNaturalist taxonomy API — the same American nonprofit dataset this model was trained on — so the app's UI, annotations, and Wikipedia reference-photo lookups all use names consistent with the rest of the app. iNaturalist's `preferred_common_name` is already correctly cased (`Cassin's Finch`) — don't re-titlecase it, `.title()` mangles the apostrophe into `Cassin'S`. Results are cached to `aiy_birds_common_names_cache.json` so repeat runs don't re-hit the API. Any name that fails to resolve falls back to the scientific name rather than failing the whole run.
3. Converts to CoreML with `coremltools`, embedding the (resolved) names directly as the classifier's labels via `ClassifierConfig`. The model's output is 965-wide, not 964 — index 964 is a "background" class (not a species) that must be kept and labeled (`"Unknown / Not a Bird"`) rather than dropped, or `ClassifierConfig`'s label count won't match the output tensor size and conversion fails. `BirdClassifier.swift` needs no changes regardless of which model backs it.
4. Zips the result to a local file plus a `manifest.json` (version, class names, source, license) — this step touches no Firebase or Supabase APIs at all.

### Running it

**This is two separate scripts in two separate virtual environments — not one step.** `coremltools` hard-requires `protobuf<=4.0.0` (no protobuf release even exists between 3.20.3 and 4.21.0, so in practice this means protobuf 3.x only), while `firebase-admin`'s dependencies require `protobuf>=4.25.8`. Those cannot be installed together: pip will either fail to resolve them, or (if forced) install a broken combination — confirmed firsthand, `coremltools` crashes at import time (`TypeError: Descriptors cannot be created directly`) against a modern protobuf. So conversion (needs `coremltools`) and publishing (needs `firebase-admin` + `boto3`) run as separate processes that hand off a file:

```bash
cd ml_pipeline

# Step 1 — convert (its own venv, no Firebase deps)
python3 -m venv .venv-convert && source .venv-convert/bin/activate
pip install -r requirements-convert.txt
python convert_photo_model.py --output ./output
deactivate

# Step 2 — publish (the main venv, no TF/coremltools deps)
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python publish_model.py --input ./output
```

Both steps only need to be run **once** (or again only if you want to re-publish, e.g. after a labelmap fix) — not on a schedule, since there's no training loop to retrigger.

`convert_photo_model.py` arguments:

| Argument | Default | Description |
|---|---|---|
| `--output` | `./output` | Directory to write `BirdClassifier.mlpackage.zip` + `manifest.json` to |
| `--skip-name-resolution` | off | Ship scientific names as-is instead of resolving common names |

`publish_model.py` arguments:

| Argument | Default | Description |
|---|---|---|
| `--input` | `./output` | Directory containing `manifest.json` + the model zip, as written by `convert_photo_model.py` |
| `--service-account` | none (uses `GOOGLE_APPLICATION_CREDENTIALS` / ADC) | Path to a Firebase service account JSON (Firestore only) |

Also needs Supabase credentials as env vars (same convention as `backend/.env.example`): `S3_ENDPOINT`, `S3_ACCESS_KEY` (the Supabase project ref), `S3_SECRET_KEY` (the service_role key), `MODEL_BUCKET` (default `birdmap-models`), `PUBLIC_S3_URL`.

### Credentials

`ml_pipeline/firestore_client.py` (used by `publish_model.py` and `live_poll.py`) resolves Firebase Admin SDK credentials in order: `--service-account <path>` → `GOOGLE_APPLICATION_CREDENTIALS` env var → Application Default Credentials. Get a service account key from Firebase Console → Project Settings → Service Accounts → Generate new private key.

### Verified

The conversion step (TF Hub download → CoreML conversion → a real inference on the resulting `.mlpackage`) has been run and verified end-to-end, producing a working 6.8 MB CoreML classifier with the exact `classLabel`/`classLabel_probs` output shape `BirdClassifier.swift`'s `VNCoreMLRequest` expects. The publish step (`publish_model.py`) has been verified only for its dependency install and imports — it hasn't been run against real Supabase/Firebase credentials, since none exist in this environment yet.

---

## Multiple birds in one photo/recording

BirdMap can flag more than one distinct bird in a single sighting:

- **Audio:** BirdNET already scores every species independently per 3-second segment rather than a single top-1 — `live_poll.py` was simply discarding everything but the best match. It now keeps every species that clears `SECONDARY_CONFIDENCE_THRESHOLD` (0.5) beyond the always-kept top result (capped at `MAX_SPECIES_REPORTED`, 3), written to the sighting doc's `aiSpeciesSuggestions` array.
- **Photo, Tier 1 (always available, no extra model):** `MultiBirdDetector.swift` runs `VNGenerateObjectnessBasedSaliencyImageRequest` (on-device Vision, no model download) to find visually salient regions beyond the main subject, crops each, and classifies the crop with the existing photo classifier. This has no concept of "bird" versus anything else salient in frame, so results are filtered hard by classifier confidence (`secondaryConfidenceThreshold`, 0.6) and deduplicated against the primary whole-image result.
- **Photo, Tier 2 (real object detector, optional):** `BirdDetector.swift` wraps a genuine object-detection CoreML model (below) that actually localizes bird-shaped regions before any species classification happens — far more reliable than saliency guessing. `MultiBirdDetector.detectAdditional` prefers Tier 2 whenever `ModelManager.isDetectorModelAvailable` is true, falling back to Tier 1 saliency otherwise. The app works correctly with neither, either, or both tiers present — Tier 2 is an additive upgrade, not a hard dependency.

Both photo tiers write into the same `aiSpeciesSuggestions` array on the sighting doc as audio (`FirebaseService.createSighting`), and both the live upload flow and revisiting a sighting later (`SightingDetailView`) show extra detections through the same `AdditionalBirdsSection` UI — confirm/correct/mark-unsure per bird, each submitting its own annotation.

### Photo detector model: Apple's CoreML catalog (YOLOv3-Tiny / COCO)

Converting an off-the-shelf COCO object detector from TensorFlow ourselves turned out not to work with current tooling — recorded here since it cost real time to establish and the failure mode isn't obvious from the docs:

- TF Hub's official detector (`tensorflow/ssd_mobilenet_v2`) bundles its box-decode + non-max-suppression as TF ops that `coremltools`'s TF frontend cannot convert — confirmed against both coremltools 7.2 and 9.0, both fail identically with `TypeError: 'numpy.float64' object cannot be interpreted as an integer` during the postprocessing subgraph's conversion.
- Older SSD models packaged as `.tflite` with the classic `TFLite_Detection_PostProcess` custom op (which historically *did* convert cleanly) are a dead end too — modern `coremltools` no longer accepts `.tflite` as an input source at all (confirmed: `ct.convert()` raises "Unable to determine the type of the model" regardless of `source=`).

Instead, `ml_pipeline/convert_bird_detector_model.py` downloads Apple's own **pre-converted** CoreML object detector directly from `developer.apple.com/machine-learning/models` (hosted at `ml-assets.apple.com`) — no TF/coremltools conversion involved at all:

| Property | Value |
|---|---|
| Publisher (hosting/distribution) | Apple |
| Original training | Joseph Redmon & Ali Farhadi, University of Washington (Darknet/YOLO) |
| Architecture | YOLOv3-Tiny |
| Training dataset | COCO (80 classes, includes `bird` at label index 14) |
| License | See [pjreddie/darknet](https://github.com/pjreddie/darknet) |
| Format | Native CoreML **pipeline** (neural network stage + built-in non-max-suppression stage) — no decode/NMS code needed on our side |
| Input | 416 × 416 RGB image |
| Size | ~35.5 MB |
| Runs | On-device, via `BirdDetector.swift` (`VNCoreMLRequest` → `VNRecognizedObjectObservation`) |

`convert_bird_detector_model.py` downloads the `.mlmodel`, verifies it's structured as expected (a pipeline whose last stage is non-max-suppression, with `bird` present among its embedded class labels — done by inspecting the spec directly, not by trusting the filename), zips it, and writes the same `manifest.json`/zip layout `publish_model.py` already expects (with `mediaType: "photo_detector"`, distinct from the classifier's `"photo"` — `publish_model.py` needed no changes, since it already keys everything off `manifest["mediaType"]`). Only needs `requests` — no TF/coremltools dependency for this one, though it's run from the same `.venv-convert` for a single documented workflow.

```bash
cd ml_pipeline
source .venv-convert/bin/activate   # same venv as convert_photo_model.py
python convert_bird_detector_model.py --output ./output_detector
deactivate

source .venv/bin/activate
python publish_model.py --input ./output_detector
```

**Verified:** the download, spec-level structural verification (pipeline shape, embedded 80-class COCO label list, `bird` present), zip, and manifest steps have all been run and confirmed end-to-end, and the iOS side (`BirdDetector.swift` + `ModelManager`'s second model slot) builds cleanly against it. Not yet verified: an actual on-device inference run against a real multi-bird photo (needs a device/simulator with the model downloaded, and `publish_model.py` needs Supabase/Firebase credentials not present in this environment — see `docs/DEPLOYMENT.md`). Until `publish_model.py` is run against real credentials, no `photo_detector` `model_versions` doc exists, `ModelManager.isDetectorModelAvailable` stays false for every install, and the app correctly runs on Tier 1 saliency alone — nothing breaks by this model simply not being published yet.

---

## Audio model: BirdNET

Runs server-side via `ml_pipeline/live_poll.py`, using [`birdnetlib`](https://github.com/kahst/BirdNET-Analyzer), a Python wrapper around the Cornell Lab of Ornithology / K. Lisa Yang Center for Conservation Bioacoustics' open-weight BirdNET model — an American academic nonprofit. **Used exactly as released, no fine-tuning.**

`birdnetlib` needs a TFLite interpreter and doesn't declare one as a hard dependency — it tries `tflite_runtime` first, falling back to `tensorflow`'s bundled `tf.lite`. `tflite-runtime` has no published wheel for several current platforms (confirmed: none for macOS/arm64), so `requirements.txt` installs full `tensorflow` instead. It also needs `librosa` for audio decoding, which — despite being an unconditional import in `birdnetlib`'s own code — isn't declared as one of its dependencies either (confirmed: importing `birdnetlib` alone fails with `ModuleNotFoundError: No module named 'librosa'`), hence the explicit pin.

This pulls `tensorflow` into the *same* environment as `firebase-admin` (for reading/writing Firestore), which is exactly the protobuf conflict described above for the photo model — except here it's resolvable: `tensorflow` only requires `protobuf<5.0.0`, not coremltools' much stricter `<=4.0.0`, and that range overlaps `firebase-admin`'s `>=4.25.8` floor. `requirements.txt` pins `protobuf>=4.25.8,<5.0.0` (verified: `4.25.9` — firebase-admin, tensorflow, birdnetlib, and sentence-transformers all import cleanly together at that pin, confirmed from a clean install).

Flow: each `live_poll.py` run queries `sightings` where `mediaType == "audio"` once. For every sighting with no `aiSpeciesSuggestion` yet, it downloads the recording with a plain HTTPS GET on its `audioURL` (a public Supabase Storage URL — no credentials needed to fetch it, unlike the old Firebase Storage Admin SDK bucket access this replaced), runs BirdNET, and writes the top prediction's species/confidence back onto the sighting doc — the same fields the on-device photo classifier fills in, so the rest of the app (review UI, map pins, `SightingDetailView`) doesn't need to know which model produced them. Scheduled by `.github/workflows/live-poll.yml` in production (every 20 minutes by default) rather than run as a persistent listener — see `docs/DEPLOYMENT.md` for why.

---

## Annotation moderation model

Also in `live_poll.py`, each run queries the `annotations` collection group for docs where `moderation == "pending"` — set by the app at submission time (`FirebaseService.submitAnnotation` in the iOS app), since Firestore can't efficiently query for a field's *absence*, only its value. For each:

1. **Pre-filter (free, no model call):** if `species` is empty or `reviewOfAI == "unsure"`, it's immediately `moderation: "ok"` — per product rule, "no annotation" and "unsure" are always legitimate, never shitposts.
2. **Otherwise:** the annotation's species/behavior/plumage text is embedded with a small local open-weight sentence-embedding model (`sentence-transformers/all-MiniLM-L6-v2`, ~80 MB, downloaded once and cached locally — no LLM API key, no per-call cost, no training) and compared via cosine similarity against two small hand-written exemplar sets: genuine bird observations vs. silly/joke/gibberish text (see `GENUINE_EXEMPLARS` / `SILLY_EXEMPLARS` in `live_poll.py`). If the "silly" similarity beats "genuine" by more than `FLAG_THRESHOLD`, the annotation is written `moderation: "flagged"`; otherwise `"ok"`.

Flagged annotations stay visible in the app (small badge in `SightingDetailView`) but are excluded from the plurality-voted "top species" shown on a sighting, so they can't skew what the community consensus looks like.

---

## Model Versioning

| Step | Detail |
|---|---|
| Upload | Zipped `.mlpackage` uploaded to **Supabase Storage** at `models/birdmap_photo_{version}.mlpackage.zip` |
| Register | A new `model_versions` Firestore doc is created with a public `downloadURL` and `isActive: true`; the previously-active doc for the same `mediaType` is flipped to `false` in the same batch |
| Discovery | iOS app queries `model_versions` (`mediaType == "photo"`, `isActive == true`) on launch and compares with the locally stored version string |
| Download | If the version differs, the app downloads directly from `downloadURL` (public, no auth needed), unzips with ZIPFoundation, replaces the local `.mlpackage`, deletes the zip |
| Cache invalidation | `ModelManager` clears its cached `MLModel` and calls `BirdClassifier.invalidateCache()` — next inference uses the new model immediately |

Only one model version is active per `mediaType` at a time (`"photo"` for the classifier, `"photo_detector"` for the Tier 2 object detector — independent version histories, independent local caches in `ModelManager`). Rolling back means manually flipping `isActive` on the desired `model_versions` doc in the Firestore console. This mechanism exists so a shipped model can be swapped (e.g. if Google publishes a newer version, or a labelmap issue needs fixing) without an App Store release — not to support a retraining loop.

---

## Why no in-house training

Earlier iterations of this pipeline fine-tuned an EfficientNet-B0/ImageNet backbone on community annotations. That's been deliberately replaced with fully static, ready-made models from vetted American organizations for both photo and audio, and the moderation model was never trained in the first place (zero-shot). Reasons this is preferable here:
- No risk of a small, early-stage annotation dataset producing a *worse* model than a well-resourced publisher's release.
- No ongoing training infrastructure, GPU time, or accuracy monitoring to maintain.
- A clean, auditable provenance chain per model (`source`/`license` fields on `model_versions` docs) — useful if there's ever a compliance review of what AI is running in the app and where its weights came from.

---

## Limitations and Future Work

| Limitation | Notes |
|---|---|
| Species coverage is whatever the upstream model covers | Google's model covers 964 species (global, not North-America-specific); BirdNET covers a large global species list too. Neither can be extended without switching to a different upstream model. |
| Tier 2 photo detector only knows "bird", not species | COCO's `bird` class is generic — it localizes bird-shaped regions, then the existing species classifier runs on each crop. A misclassified crop (e.g. two birds close together merged into one box) is a species-classifier limitation, not something more detector confidence fixes. |
| Tier 2 photo detector not yet published | `publish_model.py` hasn't been run against real Supabase/Firebase credentials in this environment — every install currently runs photo multi-bird detection on Tier 1 saliency only, until someone with credentials runs the publish step once. |
| Moderation uses hand-written exemplar phrases | Could move to a supervised classifier if enough human-reviewed `moderation` verdicts accumulate — would still need to be sourced/trained in a way consistent with the no-in-house-training decision above, or reconsidered explicitly. |
| No per-region models | Single global model each for photo and audio. |
| Polling, not real-time | `live_poll.py` runs on a 20-minute GitHub Actions schedule in production, not a persistent listener — audio ID and moderation land within one interval, not instantly. Deliberate trade for staying on free CI minutes with no always-on machine; see `docs/DEPLOYMENT.md`. |
