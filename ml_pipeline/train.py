"""
BirdMap ML training pipeline.

Fetches annotated photo sightings from Firestore, fine-tunes EfficientNet-B0
(ImageNet1K pretrained weights — not trained from scratch), exports to
CoreML, uploads the model to Firebase Storage, and registers the new version
in the `model_versions` Firestore collection.

Usage:
    python train.py --min-annotations 50

    # Bootstrap the very first model with no annotations yet, using
    # iNaturalist photos for a fixed list of common North American birds:
    python train.py --bootstrap-common-birds

    # Auto-retrain whenever N new annotated samples accumulate:
    python train.py --watch --new-annotations-threshold 100 --poll-interval 300

Credentials: see firestore_client.py — pass --service-account, set
GOOGLE_APPLICATION_CREDENTIALS, or rely on Application Default Credentials.
"""

import argparse
import hashlib
import io
import os
import platform
import tempfile
import time
import zipfile
from collections import Counter
from pathlib import Path

import coremltools as ct
import requests
import torch
import torch.nn as nn
from firebase_admin import firestore as fb_firestore
from PIL import Image
from sklearn.model_selection import train_test_split
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms
from tqdm import tqdm

import firestore_client

INATURALIST_API = "https://api.inaturalist.org/v1"

# Common North American birds by iNaturalist taxon ID → display name.
# Taxon IDs verified against the iNaturalist API; names become the class labels.
COMMON_BIRDS: dict[int, str] = {
    12727:   "American Robin",
    9083:    "Northern Cardinal",
    13473:   "Blue Jay",
    144815:  "Black-capped Chickadee",
    7089:    "Canada Goose",
    6930:    "Mallard",
    7416:    "Red-tailed Hawk",
    8229:    "American Crow",
    14850:   "European Starling",
    9182:    "House Sparrow",
    9100:    "Song Sparrow",
    9176:    "Dark-eyed Junco",
    14801:   "White-breasted Nuthatch",
    9183:    "House Finch",
    9081:    "American Goldfinch",
    9080:    "Cedar Waxwing",
    14890:   "Tufted Titmouse",
    9346:    "Baltimore Oriole",
    9325:    "Orchard Oriole",
    9744:    "Red-winged Blackbird",
    9602:    "Common Grackle",
    10373:   "Brown-headed Cowbird",
    4756:    "Turkey Vulture",
    4665:    "American Kestrel",
    116999:  "Osprey",
    4867:    "Great Blue Heron",
    4869:    "Great Egret",
    4940:    "Snowy Egret",
    5020:    "Green Heron",
    7479:    "Belted Kingfisher",
    11901:   "Barn Swallow",
    11935:   "Tree Swallow",
    11867:   "Purple Martin",
    6432:    "Ruby-throated Hummingbird",
    8104:    "Downy Woodpecker",
    1651487: "Hairy Woodpecker",
    18236:   "Northern Flicker",
    12942:   "Eastern Bluebird",
    12890:   "Hermit Thrush",
    14995:   "Gray Catbird",
    14886:   "Northern Mockingbird",
    14898:   "Brown Thrasher",
    145245:  "Yellow Warbler",
    9148:    "Common Yellowthroat",
    10247:   "American Redstart",
    9135:    "Chipping Sparrow",
    9184:    "White-throated Sparrow",
    9060:    "White-crowned Sparrow",
    9424:    "Eastern Towhee",
    10271:   "Rose-breasted Grosbeak",
    10227:   "Indigo Bunting",
    10224:   "Painted Bunting",
}

IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]

train_tf = transforms.Compose([
    transforms.RandomResizedCrop(224),
    transforms.RandomHorizontalFlip(),
    transforms.ColorJitter(0.3, 0.3, 0.3),
    transforms.ToTensor(),
    transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
])

val_tf = transforms.Compose([
    transforms.Resize(256),
    transforms.CenterCrop(224),
    transforms.ToTensor(),
    transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
])


CACHE_DIR = Path(tempfile.gettempdir()) / "birdmap_img_cache"


def _cache_path(url: str) -> Path:
    return CACHE_DIR / (hashlib.md5(url.encode()).hexdigest() + ".jpg")


def prefetch_images(samples: list[tuple[str, int]]) -> list[tuple[str, int]]:
    """Download all remote URLs to a local cache and return (local_path, label) pairs.

    Images already on disk are skipped. Failures are dropped from the dataset.
    """
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    local: list[tuple[str, int]] = []
    urls = [(url, label) for url, label in samples if not url.startswith("/")]
    disk = [(url, label) for url, label in samples if url.startswith("/")]

    print(f"  Pre-fetching {len(urls)} images to {CACHE_DIR} …")
    for url, label in tqdm(urls, desc="Downloading images"):
        path = _cache_path(url)
        if not path.exists():
            try:
                resp = requests.get(url, timeout=30)
                resp.raise_for_status()
                path.write_bytes(resp.content)
            except Exception as e:
                print(f"[prefetch] Skipping {url}: {e}")
                continue
        local.append((str(path), label))

    return disk + local


class BirdDataset(Dataset):
    def __init__(self, samples: list[tuple[str, int]], transform):
        self.samples = samples
        self.transform = transform

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        path, label = self.samples[idx]
        try:
            img = Image.open(path).convert("RGB")
            return self.transform(img), label
        except Exception as e:
            print(f"[BirdDataset] Skipping {path}: {e}")
            blank = Image.new("RGB", (224, 224))
            return self.transform(blank), label


def fetch_training_data(db, min_annotations: int):
    """Pull annotated photo sightings from Firestore and build (url, label) pairs.

    Ground truth per sighting is plurality-voted across its `annotations`
    subcollection. Annotations with no species (a submitted "unsure" review)
    or that the moderation pipeline flagged as a shitpost are excluded from
    voting — they carry no reliable species signal.
    """
    samples: list[tuple[str, str]] = []
    species_counter: Counter = Counter()

    sightings = db.collection("sightings").where("mediaType", "==", "photo").stream()
    for sighting in sightings:
        data = sighting.to_dict() or {}
        photo_url = data.get("photoURL")
        if not photo_url:
            continue

        anns = db.collection("sightings").document(sighting.id).collection("annotations").stream()
        votes: Counter = Counter()
        for ann in anns:
            a = ann.to_dict() or {}
            species = (a.get("species") or "").strip()
            if not species:
                continue
            if a.get("reviewOfAI") == "unsure":
                continue
            if a.get("moderation") == "flagged":
                continue
            votes[species] += 1

        if not votes:
            continue
        species, _ = votes.most_common(1)[0]
        samples.append((photo_url, species))
        species_counter[species] += 1

    # Filter to species with enough samples
    valid_species = {sp for sp, cnt in species_counter.items() if cnt >= min_annotations}
    samples = [(url, sp) for url, sp in samples if sp in valid_species]

    class_names = sorted(valid_species)
    label_map = {sp: i for i, sp in enumerate(class_names)}
    labeled = [(url, label_map[sp]) for url, sp in samples]
    return labeled, class_names


def fetch_inat_samples(taxon_id: int, species_name: str, per_taxon: int) -> list[tuple[str, str]]:
    """Fetch up to `per_taxon` research-grade photo URLs for one taxon from iNaturalist."""
    samples = []
    page = 1
    while len(samples) < per_taxon:
        try:
            resp = requests.get(
                f"{INATURALIST_API}/observations",
                params={
                    "taxon_id": taxon_id,
                    "quality_grade": "research",
                    "photos": "true",
                    "per_page": min(200, per_taxon - len(samples)),
                    "page": page,
                    "order_by": "votes",
                },
                timeout=30,
            )
            resp.raise_for_status()
            results = resp.json().get("results", [])
            if not results:
                break
            for obs in results:
                for photo in obs.get("photos", [])[:1]:
                    url = photo.get("url", "").replace("square", "medium")
                    if url:
                        samples.append((url, species_name))
            page += 1
        except Exception as e:
            print(f"[iNat] {species_name} page {page}: {e}")
            break
    return samples[:per_taxon]


def fetch_common_bird_samples(per_taxon: int = 80) -> list[tuple[str, str]]:
    """Return (url, species_name) pairs for all COMMON_BIRDS from iNaturalist."""
    all_samples: list[tuple[str, str]] = []
    seen_names: set[str] = set()
    unique_birds = {tid: name for tid, name in COMMON_BIRDS.items() if name not in seen_names and not seen_names.add(name)}  # type: ignore[func-returns-value]
    for taxon_id, species_name in tqdm(unique_birds.items(), desc="Fetching iNat bootstrap data"):
        samples = fetch_inat_samples(taxon_id, species_name, per_taxon)
        print(f"  {species_name}: {len(samples)} images")
        all_samples.extend(samples)
    return all_samples


def train(samples, class_names, epochs: int = 10, batch_size: int = 32):
    train_s, val_s = train_test_split(samples, test_size=0.15, random_state=42)
    train_ds = BirdDataset(train_s, train_tf)
    val_ds = BirdDataset(val_s, val_tf)

    num_workers = 0 if platform.system() == "Darwin" else 4
    train_dl = DataLoader(train_ds, batch_size=batch_size, shuffle=True, num_workers=num_workers)
    val_dl = DataLoader(val_ds, batch_size=batch_size, num_workers=num_workers)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    model = models.efficientnet_b0(weights=models.EfficientNet_B0_Weights.IMAGENET1K_V1)
    model.classifier[1] = nn.Linear(model.classifier[1].in_features, len(class_names))
    model = model.to(device)

    optimizer = torch.optim.AdamW(model.parameters(), lr=1e-4, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    criterion = nn.CrossEntropyLoss()

    best_acc = 0.0
    best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}

    for epoch in range(epochs):
        model.train()
        for imgs, labels in tqdm(train_dl, desc=f"Epoch {epoch+1}/{epochs} train"):
            imgs, labels = imgs.to(device), labels.to(device)
            optimizer.zero_grad()
            loss = criterion(model(imgs), labels)
            loss.backward()
            optimizer.step()
        scheduler.step()

        model.eval()
        correct = total = 0
        with torch.no_grad():
            for imgs, labels in val_dl:
                imgs, labels = imgs.to(device), labels.to(device)
                preds = model(imgs).argmax(dim=1)
                correct += (preds == labels).sum().item()
                total += len(labels)
        acc = correct / total if total > 0 else 0.0
        print(f"  Val accuracy: {acc:.3f}")
        if acc > best_acc:
            best_acc = acc
            best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}

    model.load_state_dict(best_state)
    return model, best_acc


class _NormalizedModel(nn.Module):
    """Wraps the classifier so it accepts raw 0-255 pixel values from CoreML ImageType."""
    def __init__(self, base: nn.Module):
        super().__init__()
        # CoreML ImageType with no scale delivers pixels as 0-255 floats, so we
        # normalise by mean*255 and std*255 to match the ImageNet training convention.
        mean = torch.tensor([m * 255.0 for m in IMAGENET_MEAN]).view(1, 3, 1, 1)
        std  = torch.tensor([s * 255.0 for s in IMAGENET_STD]).view(1, 3, 1, 1)
        self.register_buffer("mean", mean)
        self.register_buffer("std",  std)
        self.base = base

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.base((x - self.mean) / self.std)


def export_coreml(model, class_names: list[str], output_path: str):
    wrapped = _NormalizedModel(model).eval().cpu()
    # Feed 0-255 pixel values — no scale/bias in ImageType to avoid coremltools
    # broadcast bugs with per-channel or scalar scale on newer versions.
    example = torch.zeros(1, 3, 224, 224)  # zeros are safe for tracing
    traced = torch.jit.trace(wrapped, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=example.shape)],
        classifier_config=ct.ClassifierConfig(class_names),
        minimum_deployment_target=ct.target.iOS16,
    )
    mlmodel.short_description = "BirdMap bird species classifier"
    mlmodel.save(output_path)


def upload_and_register(model_path: str, version: str, class_names: list[str],
                         accuracy: float, db, bucket):
    """Zip the .mlpackage, upload it to Firebase Storage, and atomically flip
    the active `model_versions` doc for mediaType "photo" to the new one."""
    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in Path(model_path).rglob("*"):
            zf.write(f, f.relative_to(Path(model_path).parent))
    zip_buf.seek(0)

    storage_path = f"models/birdmap_photo_{version}.mlpackage.zip"
    blob = bucket.blob(storage_path)
    blob.upload_from_file(zip_buf, content_type="application/zip")
    print(f"Uploaded model to gs://{bucket.name}/{storage_path}")

    versions_ref = db.collection("model_versions")
    batch = db.batch()
    existing = versions_ref.where("mediaType", "==", "photo").where("isActive", "==", True).stream()
    for doc in existing:
        batch.update(doc.reference, {"isActive": False})
    new_ref = versions_ref.document()
    batch.set(new_ref, {
        "version": version,
        "mediaType": "photo",
        "storagePath": storage_path,
        "numClasses": len(class_names),
        "classNames": class_names,
        "accuracy": accuracy,
        "isActive": True,
        "createdAt": fb_firestore.SERVER_TIMESTAMP,
    })
    batch.commit()
    print(f"Registered model version {version} with accuracy {accuracy:.3f}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--service-account", default=None,
                        help="Path to a Firebase service account JSON. "
                             "Falls back to GOOGLE_APPLICATION_CREDENTIALS or ADC.")
    parser.add_argument("--min-annotations", type=int, default=10)
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--bootstrap-common-birds", action="store_true",
                        help="Seed training with iNaturalist images for common North American birds")
    parser.add_argument("--inat-per-species", type=int, default=80,
                        help="iNaturalist images to fetch per species when bootstrapping")
    parser.add_argument("--weights-out", default="birdmap_weights.pth",
                        help="Path to save/load trained PyTorch weights")
    parser.add_argument("--retrain", action="store_true",
                        help="Force retraining even if --weights-out already exists")
    parser.add_argument("--watch", action="store_true",
                        help="Poll for new annotations and retrain automatically")
    parser.add_argument("--new-annotations-threshold", type=int, default=100)
    parser.add_argument("--poll-interval", type=int, default=300,
                        help="Seconds between polls when --watch is set")
    args = parser.parse_args()

    import datetime

    db = firestore_client.get_db(args.service_account)
    bucket = firestore_client.get_bucket(args.service_account)

    last_sample_count = 0

    def run_once():
        nonlocal last_sample_count
        print("Fetching training data from Firestore...")
        try:
            samples, class_names = fetch_training_data(db, args.min_annotations)
            print(f"  {len(samples)} annotated samples, {len(class_names)} species")
        except Exception as e:
            if args.bootstrap_common_birds:
                print(f"  Could not fetch annotated sightings ({e}); proceeding with iNat data only.")
                samples, class_names = [], []
            else:
                print(f"Failed to fetch training data: {e}")
                return False

        if args.bootstrap_common_birds:
            print("Fetching common bird images from iNaturalist...")
            inat_samples_raw = fetch_common_bird_samples(per_taxon=args.inat_per_species)
            # Merge: iNat species + app-annotated species → unified label space
            all_species = sorted(set(class_names) | {sp for _, sp in inat_samples_raw})
            label_map = {sp: i for i, sp in enumerate(all_species)}
            # Re-encode app samples (already int labels) back to names then remap
            app_species_by_idx = {i: sp for i, sp in enumerate(class_names)}
            samples = [(url, label_map[app_species_by_idx[lbl]]) for url, lbl in samples]
            inat_samples = [(url, label_map[sp]) for url, sp in inat_samples_raw]
            samples = samples + inat_samples
            class_names = all_species
            print(f"  Combined: {len(samples)} samples, {len(class_names)} species")
        else:
            print(f"  {len(class_names)} species: {class_names[:10]}...")

        if len(class_names) < 2:
            print("Not enough species to train (need ≥ 2). "
                  "Try --bootstrap-common-birds to seed from iNaturalist.")
            return False

        if args.watch and len(samples) - last_sample_count < args.new_annotations_threshold:
            print(f"  Only {len(samples) - last_sample_count} new samples, threshold is "
                  f"{args.new_annotations_threshold}. Skipping.")
            return False

        last_sample_count = len(samples)
        print("Pre-fetching images to local disk...")
        samples = prefetch_images(samples)
        if len(samples) < 2:
            print("Not enough images downloaded to train. Exiting.")
            return False
        print(f"  {len(samples)} images ready for training.")
        weights_path = Path(args.weights_out)
        if weights_path.exists() and not args.retrain:
            print(f"Loading existing weights from {weights_path} (skip training)...")
            checkpoint = torch.load(weights_path, map_location="cpu")
            class_names = checkpoint["class_names"]
            from torchvision import models
            import torch.nn as nn
            model = models.efficientnet_b0(weights=None)
            model.classifier[1] = nn.Linear(model.classifier[1].in_features, len(class_names))
            model.load_state_dict(checkpoint["state_dict"])
            accuracy = checkpoint.get("accuracy", 0.0)
            print(f"  Loaded: {len(class_names)} classes, accuracy={accuracy:.3f}")
        else:
            print("Training model...")
            model, accuracy = train(samples, class_names, epochs=args.epochs)
            print(f"Saving weights to {weights_path}...")
            torch.save({"state_dict": model.state_dict(),
                        "class_names": class_names,
                        "accuracy": accuracy}, weights_path)

        with tempfile.TemporaryDirectory() as tmp:
            model_path = os.path.join(tmp, "BirdClassifier.mlpackage")
            print(f"Exporting CoreML model to {model_path}...")
            export_coreml(model, class_names, model_path)

            version = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d_%H%M%S")
            upload_and_register(model_path, version, class_names, accuracy, db, bucket)
        return True

    run_once()

    if args.watch:
        print(f"Watching for new annotations every {args.poll_interval}s...")
        while True:
            time.sleep(args.poll_interval)
            run_once()


if __name__ == "__main__":
    main()
