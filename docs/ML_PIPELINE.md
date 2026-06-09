# ML Pipeline

## Overview

BirdMap uses a **fine-tuned EfficientNet-B0** classifier as its bird identification model. The pipeline is designed to close a citizen science feedback loop:

1. Users submit sightings → community annotates → pipeline retrains → app updates model → better AI suggestions → users submit more confidently.

The pipeline is a single Python script (`ml_pipeline/train.py`) that can be run manually or triggered by a cron job / webhook.

---

## Model Architecture

### Base model: EfficientNet-B0

| Property | Value |
|---|---|
| Architecture | EfficientNet-B0 |
| Pretrained weights | ImageNet-1K (torchvision) |
| Input size | 224 × 224 × 3 (RGB) |
| Final layer | Linear(1280 → N_classes) — replaced at training time |
| Output | Softmax over N bird species |
| Export format | Apple CoreML `.mlpackage` |
| Minimum iOS target | iOS 16 |

EfficientNet-B0 was chosen for its accuracy-to-size ratio. The exported `.mlpackage` is typically **15–25 MB** depending on number of classes — acceptable for a background download.

---

## Training Data

### Source

Annotated sightings are fetched from the backend API. Each sighting can have multiple annotations from different users. The pipeline uses **plurality voting** to assign a single ground-truth label per sighting:

```
sighting → [annotations: Robin, Robin, Sparrow] → label: Robin
```

### Filtering

Species with fewer than `--min-annotations` samples are excluded from training. This prevents classes with only 1–2 examples from degrading model performance.

Recommended thresholds:

| Stage | `--min-annotations` |
|---|---|
| Early testing | 5 |
| First real model | 20 |
| Production quality | 50+ |

### Train / Validation split

80% training, 20% validation (stratified by species).

---

## Data Augmentation

Applied during training only:

| Augmentation | Parameters |
|---|---|
| Random resized crop | Output 224×224, scale 0.08–1.0 |
| Random horizontal flip | p=0.5 |
| Color jitter | brightness/contrast/saturation ±0.3 |
| ImageNet normalization | mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225] |

Validation uses only resize to 256 + center crop to 224 + normalization.

---

## Training Configuration

| Hyperparameter | Default | Notes |
|---|---|---|
| Optimizer | AdamW | Weight decay 1e-4 |
| Learning rate | 1e-4 | Applied to all layers (full fine-tune) |
| Scheduler | CosineAnnealingLR | T_max = num epochs |
| Epochs | 10 | Pass `--epochs` to override |
| Batch size | 32 | Reduce if OOM on CPU |
| Loss | CrossEntropyLoss | Standard multi-class |
| Checkpoint | Best validation accuracy | Saved to memory, not disk |

---

## CoreML Export

After training, the model is exported using `coremltools`:

```python
mlmodel = ct.convert(
    traced_model,
    inputs=[ct.ImageType(name="image", shape=(1, 3, 224, 224))],
    classifier_config=ct.ClassifierConfig(class_names),
    minimum_deployment_target=ct.target.iOS16,
)
```

`ClassifierConfig` embeds the species label list directly in the model — the iOS app does not need a separate label file. The output is a `.mlpackage` directory (Apple's modern model format, replacing the older `.mlmodel`).

---

## Model Versioning

Each trained model is assigned a version string based on UTC timestamp: `YYYYMMDD_HHMMSS`.

| Step | Detail |
|---|---|
| Upload | Zipped `.mlpackage` uploaded to MinIO at `models/birdmap_{version}.mlpackage.zip` |
| Register | POST `/model/register` stores version metadata in `model_versions` table |
| Activate | New version is set `is_active=True`; all previous versions set `is_active=False` |
| Discovery | iOS app polls `GET /model/version` and compares with locally stored version string |
| Download | If version differs, app downloads via presigned URL, unzips, replaces local `.mlpackage` |

Only one model version is active at any time. Rolling back requires manually updating `is_active` in the database.

---

## Running the Pipeline

### Full run

```bash
cd ml_pipeline
python train.py \
  --api-url http://localhost:8000 \
  --token "$BIRDMAP_TOKEN" \
  --min-annotations 50 \
  --epochs 10
```

### CLI arguments

| Argument | Default | Description |
|---|---|---|
| `--api-url` | `http://localhost:8000` | Backend base URL |
| `--token` | `$BIRDMAP_TOKEN` env var | JWT from a registered user (admin recommended) |
| `--min-annotations` | 10 | Minimum samples per species to include |
| `--epochs` | 10 | Training epochs |
| `--s3-endpoint` | `http://localhost:9000` | MinIO endpoint |
| `--s3-key-id` | `minioadmin` | S3 access key |
| `--s3-secret` | `minioadmin123` | S3 secret key |
| `--bucket` | `birdmap-models` | S3 bucket for model files |

### Automation (cron example)

Run nightly at 2am if there are enough new annotations:

```cron
0 2 * * * cd /opt/birdmap/ml_pipeline && python train.py --min-annotations 50 >> /var/log/birdmap_train.log 2>&1
```

---

## GPU Support

The pipeline uses `torch.device("cuda" if torch.cuda.is_available() else "cpu")`. On a machine with a CUDA GPU, training is significantly faster:

| Hardware | ~10 epoch time (100 samples/class) |
|---|---|
| M2 MacBook Pro (CPU) | ~8 minutes |
| NVIDIA RTX 3080 | ~2 minutes |
| Google Colab (T4) | ~3 minutes |

For cloud training, set `--s3-endpoint` to your production MinIO or AWS S3 endpoint and `--api-url` to your production API.

---

## Expected Performance

Performance depends heavily on dataset size and species diversity. Reference benchmarks on the CUB-200-2011 dataset (fine-grained bird classification):

| Dataset size | Species | Validation accuracy |
|---|---|---|
| 500 samples | 10 | ~75% |
| 2,000 samples | 20 | ~82% |
| 5,000 samples | 50 | ~88% |
| 10,000+ samples | 100+ | ~91%+ |

Early BirdMap deployments with limited community data will have lower accuracy. This is expected — the self-learning loop is designed to improve over time.

---

## Limitations and Future Work

| Limitation | Planned improvement |
|---|---|
| Manual pipeline trigger | Webhook from annotation count threshold (v1.2) |
| Full fine-tune (all layers) | Layer-freezing strategy for small datasets (v1.1) |
| No data validation | Flag obviously mislabelled photos via outlier detection (v2.0) |
| Single model globally | Per-region models for geographically specific species (v2.0) |
| No audio support | Integrate BirdNET for call-based identification (v1.2) |
| `unzip` via `Process` on iOS | Replace with ZipFoundation SPM package (v1.1) |
