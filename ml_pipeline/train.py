"""
BirdMap ML training pipeline.

Fetches annotated sightings from the API, fine-tunes EfficientNet-B0,
exports to CoreML, uploads the model, and registers it in the database.

Usage:
    python train.py --api-url http://localhost:8000 --min-annotations 50
"""

import argparse
import io
import os
import tempfile
import zipfile
from collections import Counter
from pathlib import Path

import boto3
import coremltools as ct
import requests
import torch
import torch.nn as nn
from PIL import Image
from sklearn.model_selection import train_test_split
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms
from tqdm import tqdm

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


class BirdDataset(Dataset):
    def __init__(self, samples: list[tuple[str, int]], transform):
        self.samples = samples
        self.transform = transform

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        url, label = self.samples[idx]
        resp = requests.get(url, timeout=30)
        img = Image.open(io.BytesIO(resp.content)).convert("RGB")
        return self.transform(img), label


def fetch_training_data(api_url: str, token: str, min_annotations: int):
    """Pull all sightings that have been annotated and build (url, label) pairs."""
    headers = {"Authorization": f"Bearer {token}"}
    sightings = requests.get(f"{api_url}/sightings?limit=5000", headers=headers).json()

    samples = []
    species_counter: Counter = Counter()

    for s in sightings:
        if s["annotation_count"] < 1:
            continue
        detail = requests.get(f"{api_url}/sightings/{s['id']}", headers=headers).json()
        if not detail["annotations"]:
            continue
        # Use plurality-voted species
        votes = Counter(a["species"] for a in detail["annotations"])
        species, _ = votes.most_common(1)[0]
        samples.append((detail["photo_url"], species))
        species_counter[species] += 1

    # Filter to species with enough samples
    valid_species = {sp for sp, cnt in species_counter.items() if cnt >= min_annotations}
    samples = [(url, sp) for url, sp in samples if sp in valid_species]

    class_names = sorted(valid_species)
    label_map = {sp: i for i, sp in enumerate(class_names)}
    labeled = [(url, label_map[sp]) for url, sp in samples]
    return labeled, class_names


def train(samples, class_names, epochs: int = 10, batch_size: int = 32):
    train_s, val_s = train_test_split(samples, test_size=0.15, random_state=42)
    train_ds = BirdDataset(train_s, train_tf)
    val_ds = BirdDataset(val_s, val_tf)

    train_dl = DataLoader(train_ds, batch_size=batch_size, shuffle=True, num_workers=4)
    val_dl = DataLoader(val_ds, batch_size=batch_size, num_workers=4)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    model = models.efficientnet_b0(weights=models.EfficientNet_B0_Weights.IMAGENET1K_V1)
    model.classifier[1] = nn.Linear(model.classifier[1].in_features, len(class_names))
    model = model.to(device)

    optimizer = torch.optim.AdamW(model.parameters(), lr=1e-4, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    criterion = nn.CrossEntropyLoss()

    best_acc = 0.0
    best_state = None

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
        acc = correct / total
        print(f"  Val accuracy: {acc:.3f}")
        if acc > best_acc:
            best_acc = acc
            best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}

    model.load_state_dict(best_state)
    return model, best_acc


def export_coreml(model, class_names: list[str], output_path: str):
    model.eval().cpu()
    example = torch.rand(1, 3, 224, 224)
    traced = torch.jit.trace(model, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=example.shape,
                             bias=[-m/s for m, s in zip(IMAGENET_MEAN, IMAGENET_STD)],
                             scale=1.0/255.0/sum(IMAGENET_STD)/3)],
        classifier_config=ct.ClassifierConfig(class_names),
        minimum_deployment_target=ct.target.iOS16,
    )
    mlmodel.short_description = "BirdMap bird species classifier"
    mlmodel.save(output_path)


def upload_and_register(model_path: str, version: str, class_names: list[str],
                         accuracy: float, api_url: str, token: str,
                         s3_endpoint: str, s3_key_id: str, s3_secret: str, bucket: str):
    # Zip the .mlpackage (it's a directory)
    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in Path(model_path).rglob("*"):
            zf.write(f, f.relative_to(Path(model_path).parent))
    zip_buf.seek(0)

    s3 = boto3.client("s3", endpoint_url=s3_endpoint,
                      aws_access_key_id=s3_key_id, aws_secret_access_key=s3_secret)
    s3_key = f"models/birdmap_{version}.mlpackage.zip"
    s3.upload_fileobj(zip_buf, bucket, s3_key)
    print(f"Uploaded model to s3://{bucket}/{s3_key}")

    # Register in DB via API
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    resp = requests.post(f"{api_url}/model/register", json={
        "version": version,
        "s3_key": s3_key,
        "num_classes": len(class_names),
        "accuracy": accuracy,
        "class_names": class_names,
    }, headers=headers)
    resp.raise_for_status()
    print(f"Registered model version {version} with accuracy {accuracy:.3f}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--api-url", default="http://localhost:8000")
    parser.add_argument("--token", default=os.environ.get("BIRDMAP_TOKEN", ""))
    parser.add_argument("--min-annotations", type=int, default=10)
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--s3-endpoint", default="http://localhost:9000")
    parser.add_argument("--s3-key-id", default="minioadmin")
    parser.add_argument("--s3-secret", default="minioadmin123")
    parser.add_argument("--bucket", default="birdmap-models")
    args = parser.parse_args()

    print("Fetching training data...")
    samples, class_names = fetch_training_data(args.api_url, args.token, args.min_annotations)
    print(f"  {len(samples)} samples, {len(class_names)} species: {class_names[:10]}...")

    if len(class_names) < 2:
        print("Not enough annotated species to train. Exiting.")
        return

    print("Training model...")
    model, accuracy = train(samples, class_names, epochs=args.epochs)

    with tempfile.TemporaryDirectory() as tmp:
        model_path = os.path.join(tmp, "BirdClassifier.mlpackage")
        print(f"Exporting CoreML model to {model_path}...")
        export_coreml(model, class_names, model_path)

        import datetime
        version = datetime.datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        upload_and_register(
            model_path, version, class_names, accuracy,
            args.api_url, args.token,
            args.s3_endpoint, args.s3_key_id, args.s3_secret, args.bucket,
        )


if __name__ == "__main__":
    main()
