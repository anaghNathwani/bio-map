# ML Pipeline

## Overview

BirdMap ships three models. **None of them are trained or fine-tuned in-house** — all are used exactly as released by their publisher, all sourced from American organizations (no Chinese-origin models or weights):

| Model | Publisher | Modality | Runs | Fine-tuned by us? |
|---|---|---|---|---|
| Bird species ID | Google (AIY Projects), Apache 2.0 | Photo | On-device (CoreML) | No — used as-is |
| Bird call ID | Cornell Lab of Ornithology (BirdNET) | Audio | Server-side (`birdnetlib`) | No — used as-is |
| Annotation moderation | `sentence-transformers` (`all-MiniLM-L6-v2`) | Text | Server-side | No — zero-shot classification via exemplar phrases, no training |

The citizen-science feedback loop:

1. User uploads a photo or recording → the relevant model predicts a species and shows a reference photo.
2. User confirms (Right), corrects (Wrong), or says Unsure, optionally adding behavior/plumage details, which becomes an annotation in Firestore.
3. A moderation pass classifies each new annotation as genuine or a "shitpost" (silly/joke content).
4. Annotations accumulate as a community dataset (plurality-voted "top species" shown per sighting, leaderboard, etc.) — but **do not retrain any model**. Recognition quality comes entirely from the upstream publisher's own pretrained model.

**All of this runs against Firestore** (`birdmap-citizenscience` project) — there is no dependency on the `backend/` FastAPI service for any of this pipeline. (`backend/` still exists for the optional Google Vision proxy and Wikipedia/eBird info lookups, which are unrelated and unaffected.)

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

This is a complete, ready-to-use classifier — **we do not train or fine-tune it**. `ml_pipeline/convert_photo_model.py` (conversion) and `publish_model.py` (Firebase publish) only *convert and republish* it:

1. Downloads the SavedModel and official labelmap from TensorFlow Hub (Google's own hosting). The SavedModel exposes two signatures for the same graph (`image_classifier`, `default`); we load it with `tf.saved_model.load()` and hand coremltools the `image_classifier` concrete function specifically, since its TF2 loader can't handle a SavedModel with more than one. Its real input placeholder is named `hub_input/images` (not `images`, despite that being the signature-level name).
2. Resolves each scientific name (e.g. `Cyanocitta cristata`) to a common name (`Blue Jay`) via the iNaturalist taxonomy API — the same American nonprofit dataset this model was trained on — so the app's UI, annotations, and Wikipedia reference-photo lookups all use names consistent with the rest of the app. iNaturalist's `preferred_common_name` is already correctly cased (`Cassin's Finch`) — don't re-titlecase it, `.title()` mangles the apostrophe into `Cassin'S`. Results are cached to `aiy_birds_common_names_cache.json` so repeat runs don't re-hit the API. Any name that fails to resolve falls back to the scientific name rather than failing the whole run.
3. Converts to CoreML with `coremltools`, embedding the (resolved) names directly as the classifier's labels via `ClassifierConfig`. The model's output is 965-wide, not 964 — index 964 is a "background" class (not a species) that must be kept and labeled (`"Unknown / Not a Bird"`) rather than dropped, or `ClassifierConfig`'s label count won't match the output tensor size and conversion fails. `BirdClassifier.swift` needs no changes regardless of which model backs it.
4. Zips the result to a local file plus a `manifest.json` (version, class names, source, license) — this step touches no Firebase APIs at all.

### Running it

**This is two separate scripts in two separate virtual environments — not one step.** `coremltools` hard-requires `protobuf<=4.0.0` (no protobuf release even exists between 3.20.3 and 4.21.0, so in practice this means protobuf 3.x only), while `firebase-admin`'s dependencies require `protobuf>=4.25.8`. Those cannot be installed together: pip will either fail to resolve them, or (if forced) install a broken combination — confirmed firsthand, `coremltools` crashes at import time (`TypeError: Descriptors cannot be created directly`) against a modern protobuf. So conversion (needs `coremltools`) and publishing (needs `firebase-admin`) run as separate processes that hand off a file:

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
| `--service-account` | none (uses `GOOGLE_APPLICATION_CREDENTIALS` / ADC) | Path to a Firebase service account JSON |

### Credentials

`ml_pipeline/firestore_client.py` (used by `publish_model.py` and `live_service.py`) resolves Firebase Admin SDK credentials in order: `--service-account <path>` → `GOOGLE_APPLICATION_CREDENTIALS` env var → Application Default Credentials. Get a service account key from Firebase Console → Project Settings → Service Accounts → Generate new private key.

### Verified

The conversion step (TF Hub download → CoreML conversion → a real inference on the resulting `.mlpackage`) has been run and verified end-to-end, producing a working 6.8 MB CoreML classifier with the exact `classLabel`/`classLabel_probs` output shape `BirdClassifier.swift`'s `VNCoreMLRequest` expects. The publish step (`publish_model.py`) has been verified only for its dependency install and imports — it hasn't been run against real Firebase credentials, since none exist in this environment yet.

---

## Audio model: BirdNET

Runs server-side via `ml_pipeline/live_service.py`, using [`birdnetlib`](https://github.com/kahst/BirdNET-Analyzer), a Python wrapper around the Cornell Lab of Ornithology / K. Lisa Yang Center for Conservation Bioacoustics' open-weight BirdNET model — an American academic nonprofit. **Used exactly as released, no fine-tuning.**

`birdnetlib` needs a TFLite interpreter and doesn't declare one as a hard dependency — it tries `tflite_runtime` first, falling back to `tensorflow`'s bundled `tf.lite`. `tflite-runtime` has no published wheel for several current platforms (confirmed: none for macOS/arm64), so `requirements.txt` installs full `tensorflow` instead. It also needs `librosa` for audio decoding, which — despite being an unconditional import in `birdnetlib`'s own code — isn't declared as one of its dependencies either (confirmed: importing `birdnetlib` alone fails with `ModuleNotFoundError: No module named 'librosa'`), hence the explicit pin.

This pulls `tensorflow` into the *same* environment as `firebase-admin` (for reading/writing Firestore), which is exactly the protobuf conflict described above for the photo model — except here it's resolvable: `tensorflow` only requires `protobuf<5.0.0`, not coremltools' much stricter `<=4.0.0`, and that range overlaps `firebase-admin`'s `>=4.25.8` floor. `requirements.txt` pins `protobuf>=4.25.8,<5.0.0` (verified: `4.25.9` — firebase-admin, tensorflow, birdnetlib, and sentence-transformers all import cleanly together at that pin, confirmed from a clean install).

Flow: `live_service.py` holds a Firestore realtime listener on `sightings` where `mediaType == "audio"`. When a new audio sighting appears with no `aiSpeciesSuggestion` yet, it downloads the recording from Firebase Storage (`sightings/{id}/audio.m4a`), runs BirdNET, and writes the top prediction's species/confidence back onto the sighting doc — the same fields the on-device photo classifier fills in, so the rest of the app (review UI, map pins, `SightingDetailView`) doesn't need to know which model produced them.

---

## Annotation moderation model

Also in `live_service.py`, a second Firestore realtime listener watches the `annotations` collection group. For each new annotation:

1. **Pre-filter (free, no model call):** if `species` is empty or `reviewOfAI == "unsure"`, it's immediately `moderation: "ok"` — per product rule, "no annotation" and "unsure" are always legitimate, never shitposts.
2. **Otherwise:** the annotation's species/behavior/plumage text is embedded with a small local open-weight sentence-embedding model (`sentence-transformers/all-MiniLM-L6-v2`, ~80 MB, downloaded once and cached locally — no LLM API key, no per-call cost, no training) and compared via cosine similarity against two small hand-written exemplar sets: genuine bird observations vs. silly/joke/gibberish text (see `GENUINE_EXEMPLARS` / `SILLY_EXEMPLARS` in `live_service.py`). If the "silly" similarity beats "genuine" by more than `FLAG_THRESHOLD`, the annotation is written `moderation: "flagged"`; otherwise `"ok"`.

Flagged annotations stay visible in the app (small badge in `SightingDetailView`) but are excluded from the plurality-voted "top species" shown on a sighting, so they can't skew what the community consensus looks like.

---

## Model Versioning

| Step | Detail |
|---|---|
| Upload | Zipped `.mlpackage` uploaded to **Firebase Storage** at `models/birdmap_photo_{version}.mlpackage.zip` |
| Register | A new `model_versions` Firestore doc is created with `isActive: true`; the previously-active doc for the same `mediaType` is flipped to `false` in the same batch |
| Discovery | iOS app queries `model_versions` (`mediaType == "photo"`, `isActive == true`) on launch and compares with the locally stored version string |
| Download | If the version differs, the app resolves a Storage download URL, downloads, unzips with ZIPFoundation, replaces the local `.mlpackage`, deletes the zip |
| Cache invalidation | `ModelManager` clears its cached `MLModel` and calls `BirdClassifier.invalidateCache()` — next inference uses the new model immediately |

Only one model version is active per `mediaType` at a time. Rolling back means manually flipping `isActive` on the desired `model_versions` doc in the Firestore console. This mechanism exists so the shipped model can be swapped (e.g. if Google publishes a newer version, or a labelmap issue needs fixing) without an App Store release — not to support a retraining loop.

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
| Moderation uses hand-written exemplar phrases | Could move to a supervised classifier if enough human-reviewed `moderation` verdicts accumulate — would still need to be sourced/trained in a way consistent with the no-in-house-training decision above, or reconsidered explicitly. |
| No per-region models | Single global model each for photo and audio. |
| Live service is single-process | `live_service.py` needs to be kept running (Terminal/cron/tmux/systemd) for audio ID and moderation to actually be "live" — it is not a managed cloud service in this pass. |
