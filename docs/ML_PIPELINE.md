# ML Pipeline

## Overview

BirdMap ships two models, both built from **existing open pretrained weights** — nothing is trained from scratch:

| Model | Base weights | Modality | Runs | Retrains? |
|---|---|---|---|---|
| Bird species ID | EfficientNet-B0, ImageNet1K (torchvision) | Photo | On-device (CoreML) | Yes — fine-tuned on community annotations |
| Bird call ID | BirdNET (Cornell K. Lisa Yang Center for Conservation Bioacoustics) | Audio | Server-side (`birdnetlib`) | No — used as-is in this pass (see [Limitations](#limitations-and-future-work)) |
| Annotation moderation | `all-MiniLM-L6-v2` sentence-embedding model | Text | Server-side | No — zero-shot classification via exemplar phrases |

The citizen-science feedback loop:

1. User uploads a photo or recording → the relevant model predicts a species and shows a reference photo.
2. User confirms (Right), corrects (Wrong), or says Unsure, optionally adding behavior/plumage details, which becomes an annotation in Firestore.
3. A moderation pass classifies each new annotation as genuine or a "shitpost" (silly/joke content) before it's allowed to influence training.
4. The photo model periodically retrains on plurality-voted, non-flagged annotations and republishes a new version; the app picks it up on next launch.

**All of this runs against Firestore** (`birdmap-citizenscience` project) — there is no dependency on the `backend/` FastAPI service for any of this pipeline. (`backend/` still exists for the optional Google Vision proxy and Wikipedia/eBird info lookups, which are unrelated and unaffected.)

---

## Photo model: EfficientNet-B0

| Property | Value |
|---|---|
| Architecture | EfficientNet-B0 |
| Pretrained weights | ImageNet-1K (torchvision) |
| Input size | 224 × 224 × 3 (RGB) |
| Final layer | Linear(1280 → N_classes) — replaced at training time |
| Output | Softmax over N bird species |
| Export format | Apple CoreML `.mlpackage` |
| Minimum iOS target | iOS 16 |
| Runs | On-device, via `BirdClassifier.swift` (Vision + CoreML) |

### Training data

Annotated photo sightings are read directly from Firestore (`ml_pipeline/train.py`, `fetch_training_data()`): each `sightings/{id}` doc with `mediaType == "photo"` is joined with its `annotations` subcollection, and the ground-truth label is the **plurality vote** across annotations:

```
sighting → annotations: [Robin, Robin, Sparrow] → label: Robin
```

Excluded from voting (they carry no reliable species signal):
- Annotations with an empty `species` (a submitted "Unsure" review)
- Annotations flagged `moderation == "flagged"` by the moderation pass

Species with fewer than `--min-annotations` samples are dropped (default 10; use higher for production quality — see the original recommendations table below).

| Stage | `--min-annotations` |
|---|---|
| Early testing | 5 |
| First real model | 20 |
| Production quality | 50+ |

80/20 stratified train/validation split; standard ImageNet augmentation during training (random resized crop, horizontal flip, color jitter), resize+center-crop only for validation.

### Bootstrapping the first model

With zero annotations, there's nothing to train on. `--bootstrap-common-birds` seeds training with iNaturalist research-grade photos for a fixed list of ~50 common North American species (`COMMON_BIRDS` in `train.py`), merged with any real annotated species already present. This produces the **first working base model** — this is what should be run once, up front, so a fresh app install has something real to download.

```bash
cd ml_pipeline
pip install -r requirements.txt
python train.py --bootstrap-common-birds
```

### Publishing a new version

`export_coreml()` traces the fine-tuned model, wraps it to accept raw 0–255 pixel input (see `_NormalizedModel`, which folds ImageNet mean/std normalization into the traced graph so CoreML's `ImageType` preprocessing doesn't need per-channel scale/bias), and converts with `coremltools`. `ClassifierConfig` embeds the species label list directly in the model.

`upload_and_register()` then:
1. Zips the `.mlpackage` and uploads it to **Firebase Storage** at `models/birdmap_photo_{version}.mlpackage.zip`.
2. Writes a new doc to the **`model_versions`** Firestore collection (`version`, `mediaType: "photo"`, `storagePath`, `numClasses`, `classNames`, `accuracy`, `isActive: true`, `createdAt`), atomically flipping any previously-active photo model doc to `isActive: false` in the same batch.

The iOS app's `ModelManager.checkForUpdate()` queries `model_versions` for the active photo model on launch, downloads the zip from Storage if the version changed, unzips it, and invalidates `BirdClassifier`'s cached model.

### Running the pipeline

```bash
cd ml_pipeline
python train.py --min-annotations 50 --epochs 10

# Retrain automatically whenever enough new annotated samples accumulate:
python train.py --watch --new-annotations-threshold 100 --poll-interval 300
```

| Argument | Default | Description |
|---|---|---|
| `--service-account` | none (uses `GOOGLE_APPLICATION_CREDENTIALS` / ADC) | Path to a Firebase service account JSON |
| `--min-annotations` | 10 | Minimum samples per species to include |
| `--epochs` | 10 | Training epochs |
| `--bootstrap-common-birds` | off | Seed with iNaturalist images for common species |
| `--inat-per-species` | 80 | iNaturalist images to fetch per species when bootstrapping |
| `--watch` | off | Poll for new annotations and retrain automatically |
| `--new-annotations-threshold` | 100 | Minimum new samples before `--watch` retrains |
| `--poll-interval` | 300 | Seconds between polls when `--watch` is set |

This is a **self-hosted script** — run it manually or on a cron/`--watch` loop on any machine with network access to Firestore/Storage (your laptop, a cheap always-on box, etc). It does not require Cloud Functions or the Blaze plan by itself, though Firebase Storage (used for both sighting uploads and model hosting) does require Blaze to be enabled on this project regardless.

### Credentials

`ml_pipeline/firestore_client.py` resolves Firebase Admin SDK credentials in order: `--service-account <path>` → `GOOGLE_APPLICATION_CREDENTIALS` env var → Application Default Credentials. Get a service account key from Firebase Console → Project Settings → Service Accounts → Generate new private key.

---

## Audio model: BirdNET

Runs server-side via `ml_pipeline/live_service.py`, using [`birdnetlib`](https://github.com/kahst/BirdNET-Analyzer), a Python wrapper around Cornell's open-weight BirdNET model. Unlike the photo model, **BirdNET's weights are used as-is in this pass** — they are not fine-tuned on BirdMap's own audio annotations (see [Limitations](#limitations-and-future-work)).

Flow: `live_service.py` holds a Firestore realtime listener on `sightings` where `mediaType == "audio"`. When a new audio sighting appears with no `aiSpeciesSuggestion` yet, it downloads the recording from Firebase Storage (`sightings/{id}/audio.m4a`), runs BirdNET, and writes the top prediction's species/confidence back onto the sighting doc — the same fields the on-device photo classifier fills in, so the rest of the app (review UI, map pins, `SightingDetailView`) doesn't need to know which model produced them.

---

## Annotation moderation model

Also in `live_service.py`, a second Firestore realtime listener watches the `annotations` collection group. For each new annotation:

1. **Pre-filter (free, no model call):** if `species` is empty or `reviewOfAI == "unsure"`, it's immediately `moderation: "ok"` — per product rule, "no annotation" and "unsure" are always legitimate, never shitposts.
2. **Otherwise:** the annotation's species/behavior/plumage text is embedded with a small local open-weight sentence-embedding model (`sentence-transformers/all-MiniLM-L6-v2`, ~80 MB, downloaded once and cached locally — no LLM API key, no per-call cost, no training from scratch) and compared via cosine similarity against two small hand-written exemplar sets: genuine bird observations vs. silly/joke/gibberish text (see `GENUINE_EXEMPLARS` / `SILLY_EXEMPLARS` in `live_service.py`). If the "silly" similarity beats "genuine" by more than `FLAG_THRESHOLD`, the annotation is written `moderation: "flagged"`; otherwise `"ok"`.

Flagged annotations stay visible in the app (small badge in `SightingDetailView`) but are excluded from the photo model's plurality-vote training labels, so they can't poison retraining.

---

## Model Versioning

| Step | Detail |
|---|---|
| Upload | Zipped `.mlpackage` uploaded to **Firebase Storage** at `models/birdmap_photo_{version}.mlpackage.zip` |
| Register | A new `model_versions` Firestore doc is created with `isActive: true`; the previously-active doc for the same `mediaType` is flipped to `false` in the same batch |
| Discovery | iOS app queries `model_versions` (`mediaType == "photo"`, `isActive == true`) on launch and compares with the locally stored version string |
| Download | If the version differs, the app resolves a Storage download URL, downloads, unzips with ZIPFoundation, replaces the local `.mlpackage`, deletes the zip |
| Cache invalidation | `ModelManager` clears its cached `MLModel` and calls `BirdClassifier.invalidateCache()` — next inference uses the new model immediately |

Only one model version is active per `mediaType` at a time. Rolling back means manually flipping `isActive` on the desired `model_versions` doc in the Firestore console.

---

## Expected Performance

Performance depends heavily on dataset size and species diversity. Reference benchmarks on the CUB-200-2011 dataset (fine-grained bird classification):

| Dataset size | Species | Validation accuracy |
|---|---|---|
| 500 samples | 10 | ~75% |
| 2,000 samples | 20 | ~82% |
| 5,000 samples | 50 | ~88% |
| 10,000+ samples | 100+ | ~91%+ |

Early BirdMap deployments with limited community data will have lower accuracy — that's expected, and why the photo model bootstraps from iNaturalist rather than shipping empty.

---

## Limitations and Future Work

| Limitation | Planned improvement |
|---|---|
| Audio model isn't fine-tuned | BirdNET runs as-is; a future pass could fine-tune its classifier head on plurality-voted audio annotations the same way the photo model retrains |
| Moderation uses hand-written exemplar phrases | Once enough human-reviewed `moderation` verdicts accumulate, they could train a small supervised classifier instead of zero-shot similarity |
| Photo retraining is a manual/cron trigger | Could move to a webhook or scheduled job once the pipeline needs less babysitting |
| No per-region models | Single global model — geographically-specific species models are a possible v2 |
| Live service is single-process | `live_service.py` needs to be kept running (Terminal/cron/tmux/systemd) for audio ID and moderation to actually be "live" — it is not a managed cloud service in this pass |
