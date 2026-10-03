# ML Pipeline

## Overview

BirdRadar ships four models, all originally sourced from vetted American organizations (no Chinese-origin models or weights). **As of this writing, all four still run exactly as released by their publisher** — but this is a transition state, not the policy. Company policy has changed from "nothing is trained in-house" to **fine-tuning (and where useful, quantizing) these pretrained weights on our own community-annotation data**, funded by and triggered on annotation volume, once there's enough of it to be worth doing. See "Our in-house training policy" below for what's actually live today versus what's designed but not yet built.

| Model | Publisher | Modality | Runs | Fine-tuned by us? |
|---|---|---|---|---|
| Bird species ID | Google (AIY Projects), Apache 2.0 | Photo | On-device (TFLite — the CoreML conversion of this model is broken, see below) | Not yet — planned as part of a combined detector+classifier model, see below |
| Multi-bird photo detector (Tier 2) | Apple (pre-converted CoreML catalog); YOLOv3-Tiny trained on COCO by Redmon/Farhadi, U. Washington | Photo | On-device (CoreML) | Not yet — same combined-model plan as above; optional, see below |
| Bird call ID | Cornell Lab of Ornithology (BirdNET) | Audio | On-device (TFLite) — `birdnetlib`/`live_poll.py` is a server-side fallback for recordings the device couldn't classify | No fine-tuning planned — used as-is |
| Annotation moderation | Bundled bird-name list (~7,400 names), hand-written heuristic | Text | On-device — a dormant server-side `sentence-transformers` pass exists but no longer receives any work (see below) | No model to fine-tune; it's a name-matching heuristic, not a trained classifier |

The citizen-science feedback loop:

1. User uploads a photo or recording → the relevant model predicts a species (or, for photos/audio with more than one bird, several) and shows a reference photo per species. Both photo and audio classification run on-device; audio only falls back to the server if on-device classification fails or can't run (a recording with no bird is a normal on-device result and isn't retried).
2. User confirms (Right), corrects (Wrong), or says Unsure for each suggestion, optionally adding behavior/plumage details, which becomes an annotation in Firestore.
3. Each viewer's device judges whether an annotation looks like a genuine bird name or a "shitpost" (silly/joke content) the moment its card is shown — see "Annotation moderation" below.
4. Annotations accumulate as a community dataset (plurality-voted "top species" shown per sighting, leaderboard, etc.) and now also count toward the training trigger described below — `ml_pipeline/check_training_trigger.py` checks every 20 minutes whether 500 more processed annotations have accumulated since the last training run. Today that check only logs; it doesn't yet kick off training or change what any model predicts (see below for what's still planned).

**Firestore** (`birdmap-citizenscience` project) is the database *and* the blob store for all of this — no Firebase Storage (which needs a linked Blaze billing account for any usage) and no third-party storage either. Sighting photo/audio bytes are compressed client-side and embedded as a base64 data URI directly in the sighting document (`FirebaseService.uploadImage`/`uploadAudio` in the iOS app — no backend involved). Model files are the same idea scaled up: too large for one 1 MiB Firestore document, so they're split into base64 chunk documents under a `chunks` subcollection and reassembled on-device (`publish_model.py`, `ModelManager.swift`). This pattern follows github.com/ishanvi-dekate/team-efficient-epp (Profile.jsx's avatar upload, ChatBot.jsx's imageToBase64), which used the same trick to avoid Storage entirely. See `docs/DEPLOYMENT.md`.

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

This is a complete, ready-to-use classifier — **we do not train or fine-tune it**. `ml_pipeline/convert_photo_model.py` (conversion) and `publish_model.py` (chunked Firestore publish, no Storage) only *convert and republish* it:

1. Downloads the SavedModel and official labelmap from TensorFlow Hub (Google's own hosting). The SavedModel exposes two signatures for the same graph (`image_classifier`, `default`); we load it with `tf.saved_model.load()` and hand coremltools the `image_classifier` concrete function specifically, since its TF2 loader can't handle a SavedModel with more than one. Its real input placeholder is named `hub_input/images` (not `images`, despite that being the signature-level name).
2. Resolves each scientific name (e.g. `Cyanocitta cristata`) to a common name (`Blue Jay`) via the iNaturalist taxonomy API — the same American nonprofit dataset this model was trained on — so the app's UI, annotations, and Wikipedia reference-photo lookups all use names consistent with the rest of the app. iNaturalist's `preferred_common_name` is already correctly cased (`Cassin's Finch`) — don't re-titlecase it, `.title()` mangles the apostrophe into `Cassin'S`. Results are cached to `aiy_birds_common_names_cache.json` so repeat runs don't re-hit the API. Any name that fails to resolve falls back to the scientific name rather than failing the whole run.
3. Converts to CoreML with `coremltools`, embedding the (resolved) names directly as the classifier's labels via `ClassifierConfig`. The model's output is 965-wide, not 964 — index 964 is a "background" class (not a species) that must be kept and labeled (`"Unknown / Not a Bird"`) rather than dropped, or `ClassifierConfig`'s label count won't match the output tensor size and conversion fails. `BirdClassifier.swift` needs no changes regardless of which model backs it.
4. Zips the result to a local file plus a `manifest.json` (version, class names, source, license) — this step touches no Firebase APIs at all.

### Running it

**This is two separate scripts in two separate virtual environments — not one step.** `coremltools` hard-requires `protobuf<=4.0.0` (no protobuf release even exists between 3.20.3 and 4.21.0, so in practice this means protobuf 3.x only), while `firebase-admin`'s dependencies require `protobuf>=4.25.8`. Those cannot be installed together: pip will either fail to resolve them, or (if forced) install a broken combination — confirmed firsthand, `coremltools` crashes at import time (`TypeError: Descriptors cannot be created directly`) against a modern protobuf. So conversion (needs `coremltools`) and publishing (needs only `firebase-admin` — no Storage SDK, no S3 client) run as separate processes that hand off a file:

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

No other credentials needed — the model zip is read straight off disk and written into Firestore as base64 chunk documents (`CHUNK_SIZE = 650_000` raw bytes per chunk, comfortably under Firestore's 1 MiB per-document cap after base64's ~4/3 inflation).

### Credentials

`ml_pipeline/firestore_client.py` (used by `publish_model.py` and `live_poll.py`) resolves Firebase Admin SDK credentials in order: `--service-account <path>` → `GOOGLE_APPLICATION_CREDENTIALS` env var → Application Default Credentials. Get a service account key from Firebase Console → Project Settings → Service Accounts → Generate new private key.

### Verified

The conversion step (TF Hub download → CoreML conversion → a real inference on the resulting `.mlpackage`) has been run and verified end-to-end, producing a working 6.8 MB CoreML classifier with the exact `classLabel`/`classLabel_probs` output shape `BirdClassifier.swift`'s `VNCoreMLRequest` expects — at 650 KB/chunk that's ~11 chunk documents. The publish step (`publish_model.py`) has been verified only for its dependency install, imports, and chunking/reassembly logic — it hasn't been run against a real Firebase project from this environment (no network path to it here — see chat history), so it needs a real run on a machine with normal network access before the app has an actual model to download.

---

## Multiple birds in one photo/recording

BirdRadar can flag more than one distinct bird in a single sighting:

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

**Verified:** the download, spec-level structural verification (pipeline shape, embedded 80-class COCO label list, `bird` present), zip, and manifest steps have all been run and confirmed end-to-end, and the iOS side (`BirdDetector.swift` + `ModelManager`'s second model slot) builds cleanly against it. Not yet verified: an actual on-device inference run against a real multi-bird photo, and **`publish_model.py` hasn't actually been run against the real Firebase project** — this environment has no network path to it (see chat history), not a dependency gap: publishing needs only Firebase Admin credentials now (no Supabase/Storage involved at all since the switch to chunked Firestore storage), so it just needs running once from a machine with normal network access. Until that happens, no `photo_detector` `model_versions` doc exists, `ModelManager.isDetectorModelAvailable` stays false for every install, and the app correctly runs on Tier 1 saliency alone — nothing breaks by this model simply not being published yet.

---

## Audio model: BirdNET

**Primary path is on-device now.** `ML/BirdNETClassifier.swift` runs BirdNET V2.4 via TFLite (`ML/Bundled/BundledBirdNET.tflite`, 51.7 MB) the moment a recording stops, plus a location/season meta-model (`BundledBirdNETLocation.tflite`, 14.8 MB) fed the device's real GPS fix to rule out species that don't live nearby — without that filter BirdNET names implausible species for noise. Sound classes (human voice, dog, engine, crickets, etc.) are blanked from `BundledBirdNETLabels.json` by `ml_pipeline/build_birdnet_labels.py`. Confidence floor is 0.2 with a GPS fix, 0.35 without. A sighting resolved this way is stamped `aiAnalyzedAt` on the sighting doc.

**`ml_pipeline/live_poll.py`'s server-side pass is now a fallback**, using [`birdnetlib`](https://github.com/kahst/BirdNET-Analyzer), a Python wrapper around the Cornell Lab of Ornithology / K. Lisa Yang Center for Conservation Bioacoustics' open-weight BirdNET model — an American academic nonprofit. **Used exactly as released, no fine-tuning**, same as the on-device copy.

`birdnetlib` needs a TFLite interpreter and doesn't declare one as a hard dependency — it tries `tflite_runtime` first, falling back to `tensorflow`'s bundled `tf.lite`. `tflite-runtime` has no published wheel for several current platforms (confirmed: none for macOS/arm64), so `requirements.txt` installs full `tensorflow` instead. It also needs `librosa` for audio decoding, which — despite being an unconditional import in `birdnetlib`'s own code — isn't declared as one of its dependencies either (confirmed: importing `birdnetlib` alone fails with `ModuleNotFoundError: No module named 'librosa'`), hence the explicit pin.

This pulls `tensorflow` into the *same* environment as `firebase-admin` (for reading/writing Firestore), which is exactly the protobuf conflict described above for the photo model — except here it's resolvable: `tensorflow` only requires `protobuf<5.0.0`, not coremltools' much stricter `<=4.0.0`, and that range overlaps `firebase-admin`'s `>=4.25.8` floor. `requirements.txt` pins `protobuf>=4.25.8,<5.0.0` (verified: `4.25.9` — firebase-admin, tensorflow, birdnetlib, and sentence-transformers all import cleanly together at that pin, confirmed from a clean install).

Flow: each `live_poll.py` run queries `sightings` where `mediaType == "audio"` once. For every sighting with no `aiSpeciesSuggestion` yet **and no `aiAnalyzedAt`** (i.e. the on-device classifier didn't already resolve it — most recordings, so most runs now do nothing for audio), it decodes the recording directly from its `audioURL` field (a `data:audio/mp4;base64,...` URI embedded on the sighting doc itself — see `FirebaseService.uploadAudio` in the iOS app — no network fetch, no Storage, no backend involved), runs BirdNET, and writes the top prediction's species/confidence back onto the sighting doc — the same fields the on-device classifier fills in, so the rest of the app (review UI, map pins, `SightingDetailView`) doesn't need to know which one produced them. Scheduled by `.github/workflows/live-poll.yml` in production (every 20 minutes by default) rather than run as a persistent listener — see `docs/DEPLOYMENT.md` for why. Recording length is capped at 30s client-side (`AudioRecorderViewModel.maxRecordingSeconds`) specifically so the base64-encoded audio can't blow past Firestore's 1 MiB document limit.

---

## Annotation moderation

**Runs entirely on-device now.** `ML/AnnotationModerator.swift` decides whether an annotation's species looks like a real bird name on each viewer's own device, at the moment an annotation card is shown — nothing is written back to Firestore, so there's no stored verdict a client could tamper with, and the annotation form warns the author before they submit a non-bird. It matches the submitted species text against the ~7,400 bird names already bundled for identification: exact match, typo (edit distance), a known name embedded in a longer phrase, or a generic bird word ("sparrow", "hawk sp."), with explicit joke words/phrases as vetoes. Everything else is flagged — a label shown in the UI, never a deletion. Empty species and `reviewOfAI == "unsure"` are always treated as legitimate, per the same product rule the old server-side version used. Measure any change with `ios/BirdRadar/Tools/ModerationEval/run.sh` (every bundled bird name must pass; genuine/silly test cases live in `cases.json`).

Flagged annotations stay visible in the app (small badge in `SightingDetailView`) but are excluded from the plurality-voted "top species" shown on a sighting — computed identically on every device that renders it, so consensus can't skew based on who's viewing.

**The old server-side pass is dormant, not deleted.** `live_poll.py` still contains a `poll_moderation()` step that queries the `annotations` collection group for docs where `moderation == "pending"` and, for each, embeds the annotation's text with a local sentence-embedding model (`sentence-transformers/all-MiniLM-L6-v2`, ~80 MB) and compares it via cosine similarity against hand-written "genuine" vs. "silly" exemplar sets (see `GENUINE_EXEMPLARS`/`SILLY_EXEMPLARS` in `live_poll.py`), writing `moderation`/`moderationScore` back if the "silly" side wins by more than `FLAG_THRESHOLD`. But `FirebaseService.submitAnnotation()` in the iOS app no longer sets `moderation: "pending"` on submission — moderation moved on-device instead — so this query now always returns zero documents. `sentence-transformers`/`torch` could be dropped from `requirements.txt` and this step deleted; it hasn't been yet.

---

## Model Versioning

| Step | Detail |
|---|---|
| Upload | Zipped `.mlpackage` split into ~650 KB chunks, each base64-encoded and written as its own doc under `model_versions/{id}/chunks/{index}` |
| Register | A new `model_versions` Firestore doc is created with `chunkCount`, `totalBytes`, and `isActive: true`; the previously-active doc for the same `mediaType` is flipped to `false` in the same batch |
| Discovery | iOS app queries `model_versions` (`mediaType == "photo"`, `isActive == true`) on launch and compares with the locally stored version string |
| Download | If the version differs, the app reads every doc in that version's `chunks` subcollection ordered by `index`, base64-decodes each independently (chunk boundaries don't align to base64's 3-byte groups, so decoding must happen per-chunk, not on the concatenated base64 strings), concatenates the raw bytes, unzips with ZIPFoundation, replaces the local `.mlpackage`, deletes the temp zip |
| Cache invalidation | `ModelManager` clears its cached `MLModel` and calls `BirdClassifier.invalidateCache()` — next inference uses the new model immediately |

Only one model version is active per `mediaType` at a time (`"photo"` for the classifier, `"photo_detector"` for the Tier 2 object detector — independent version histories, independent local caches in `ModelManager`). Rolling back means manually flipping `isActive` on the desired `model_versions` doc in the Firestore console. This mechanism exists so a shipped model can be swapped (e.g. if Google publishes a newer version, or a labelmap issue needs fixing) without an App Store release — not to support a retraining loop.

---

## Our in-house training policy

Earlier iterations of this pipeline fine-tuned an EfficientNet-B0/ImageNet backbone on community annotations. That was deliberately replaced with fully static, ready-made models — no risk of a small, early-stage annotation dataset producing a *worse* model than a well-resourced publisher's release; no training/GPU/monitoring infrastructure to maintain; a clean, auditable provenance chain per model (`source`/`license` fields on `model_versions` docs) for compliance purposes.

That reasoning held while the annotation dataset was small. It no longer reflects company policy: **we now spend resources fine-tuning existing pretrained weights (and quantizing them for on-device use) for better on-device bird identification**, funded by and triggered on community annotation volume rather than run continuously. Two things are true at once, and both matter:

- **The trigger mechanism is live.** `ml_pipeline/check_training_trigger.py` runs every 20 minutes (`.github/workflows/live-poll.yml`'s `check-training-trigger` job), counting newly-processed annotations against a per-model `lastTrainedCount` stored in Firestore (`meta/combinedModelTraining`, `meta/moderationModelTraining`), and logs when 500 new annotations have accumulated since the last training run.
- **No training or publishing code exists yet.** The trigger currently only observes and logs — it doesn't train anything, doesn't call `publish_model.py`, and doesn't advance `lastTrainedCount`. Two follow-on pieces were designed but deliberately not yet built, so real annotation volume could inform their parameters first:
  - ~~A trained classifier for annotation moderation~~ — **superseded, not just unbuilt.** This was planned as a model trained on accumulated `moderation` verdicts, but moderation has since moved fully on-device (see "Annotation moderation" above) and the app no longer writes `moderation: "pending"` on new annotations. The `moderation` target's count query (`get_processed_annotation_count` in `check_training_trigger.py`) only matches annotations that *have* a `moderation` field set — annotations written since the switch have none, so that count has effectively frozen and won't grow from real usage. This plan needs to either be dropped, or redesigned around the on-device heuristic's output instead of a field nothing writes anymore.
  - A combined detector+classifier model — a single fine-tuned model that outputs bounding box + species in one pass, replacing today's two-stage Tier 1/2 detector → classifier pipeline, using the existing MobileNetV2/YOLOv3-Tiny models' own outputs as pseudo-labels where no ground truth exists. Unaffected by the moderation change above.

Until the detector+classifier model lands, recognition quality still comes entirely from the upstream publishers' pretrained models, same as before this policy changed.

---

## Limitations and Future Work

| Limitation | Notes |
|---|---|
| Species coverage is whatever the upstream model covers | Google's model covers 964 species (global, not North-America-specific); BirdNET covers a large global species list too. Neither can be extended without switching to a different upstream model. |
| Tier 2 photo detector only knows "bird", not species | COCO's `bird` class is generic — it localizes bird-shaped regions, then the existing species classifier runs on each crop. A misclassified crop (e.g. two birds close together merged into one box) is a species-classifier limitation, not something more detector confidence fixes. |
| Tier 2 photo detector not yet published | `publish_model.py` hasn't actually been run against the real Firebase project yet (this dev environment has no network path to it) — every install currently runs photo multi-bird detection on Tier 1 saliency only. Needs a one-time run from a machine with normal network access, not a code fix. |
| Moderation is a name-matching heuristic, not a trained classifier | Runs on-device (`AnnotationModerator.swift`) against the ~7,400 bundled bird names plus joke-word vetoes. The originally planned successor — a classifier trained on accumulated `moderation` verdicts — is now blocked, not just unbuilt: the app no longer writes that field, so there's nothing left to accumulate. See "Our in-house training policy" above. |
| Combined detector+classifier model not yet built | Designed (pseudo-labels from Tier 2's own boxes + community-confirmed species, MobileNetV2 backbone trained from scratch — not continuing from the deployed classifier's exact weights, which aren't available as loadable PyTorch weights), scoped to land after real annotation volume from the trigger above informs its species-coverage thresholds. |
| No per-region models | Single global model each for photo and audio. |
| Polling, not real-time — for the fallback path only | `live_poll.py` runs on a 20-minute GitHub Actions schedule in production, not a persistent listener. Photo ID and (usually) audio ID are instant now, on-device; only a recording the on-device BirdNET model couldn't classify waits for this schedule. Deliberate trade for staying on free CI minutes with no always-on machine; see `docs/DEPLOYMENT.md`. |
