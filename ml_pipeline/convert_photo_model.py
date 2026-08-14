"""
Converts the BirdMap photo model. Does NOT touch Firebase — see publish_model.py
for that step. Split into two scripts/two venvs deliberately: `coremltools`
hard-requires protobuf<=4.0.0 (no protobuf release even exists between 3.20.3
and 4.21.0, so this really means "protobuf 3.x only"), while `firebase-admin`
requires protobuf>=4.25.8. Those cannot be installed together — pip will
either fail to resolve them or silently install a broken combination
(confirmed: coremltools crashes at import time with a modern protobuf).
Run this in a venv from requirements-convert.txt, then run publish_model.py
in a *separate* venv from requirements.txt to actually ship the result.

This does NOT train anything. It takes Google's AIY "Birds V1" bird species
classifier (MobileNetV2, trained on the iNaturalist 2017 dataset, Apache 2.0,
published by Google on TensorFlow Hub) exactly as released and converts it to
CoreML. No fine-tuning, no in-house training loop — see docs/ML_PIPELINE.md.

Steps:
  1. Download the SavedModel + official labelmap from TensorFlow Hub (Google).
  2. Resolve each scientific name in the labelmap to a common name via the
     iNaturalist taxonomy API (Visipedia/iNaturalist, an American nonprofit
     initiative — the same dataset this model was trained on), so the app
     shows "Blue Jay" rather than "Cyanocitta cristata". Cached to disk so
     repeat runs don't re-hit the API. Falls back to the scientific name for
     any species that fails to resolve.
  3. Convert to CoreML with coremltools, embedding the (resolved) names
     directly in the classifier so BirdClassifier.swift needs no changes.
  4. Zip the result and write a manifest.json next to it, both under --output.

Usage:
    python convert_photo_model.py
    python convert_photo_model.py --output ./out --skip-name-resolution
"""

import argparse
import csv
import datetime
import io
import json
import tarfile
import tempfile
import time
import zipfile
from pathlib import Path

import coremltools as ct
import requests
import tensorflow as tf
from tqdm import tqdm

MODEL_SOURCE = "Google AIY Birds V1 (MobileNetV2, trained on iNaturalist 2017 dataset)"
MODEL_LICENSE = "Apache 2.0"
SAVEDMODEL_URL = "https://tfhub.dev/google/aiy/vision/classifier/birds_V1/1?tf-hub-format=compressed"
LABELMAP_URL = "https://www.gstatic.com/aihub/tfhub/labelmaps/aiy_birds_V1_labelmap.csv"
INATURALIST_API = "https://api.inaturalist.org/v1"

INPUT_SIZE = 224
NAME_CACHE_PATH = Path(__file__).parent / "aiy_birds_common_names_cache.json"


def download_savedmodel(dest_dir: Path) -> Path:
    print(f"Downloading SavedModel from TensorFlow Hub ({SAVEDMODEL_URL})...")
    resp = requests.get(SAVEDMODEL_URL, timeout=120)
    resp.raise_for_status()
    dest_dir.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(resp.content), mode="r:gz") as tf_archive:
        tf_archive.extractall(dest_dir)

    # TF Hub's compressed download is usually a SavedModel at the archive root,
    # but be defensive in case it's nested a level down.
    if (dest_dir / "saved_model.pb").exists():
        savedmodel_root = dest_dir
    else:
        matches = list(dest_dir.rglob("saved_model.pb"))
        if not matches:
            raise RuntimeError(
                f"Could not find saved_model.pb anywhere under {dest_dir} — "
                "the TF Hub archive layout may have changed; inspect it manually."
            )
        savedmodel_root = matches[0].parent

    print(f"  Extracted SavedModel to {savedmodel_root}")
    return savedmodel_root


BACKGROUND_LABEL = "Unknown / Not a Bird"


def download_labelmap() -> list[str]:
    """Returns all 965 labels ordered by class index (0..963 species, 964
    background) — the model's output tensor is 965-wide, so CoreML's
    ClassifierConfig needs exactly 965 labels or conversion fails with a
    size-mismatch error. The "background" class (964) is given a friendly
    name rather than resolved via iNaturalist (it isn't a real species)."""
    print("Downloading official labelmap...")
    resp = requests.get(LABELMAP_URL, timeout=30)
    resp.raise_for_status()
    reader = csv.DictReader(io.StringIO(resp.text))
    by_id: dict[int, str] = {}
    for row in reader:
        idx = int(row["id"])
        name = row["name"].strip()
        by_id[idx] = BACKGROUND_LABEL if name.lower() == "background" else name
    class_names = [by_id[i] for i in sorted(by_id)]
    print(f"  {len(class_names)} labels ({len(class_names) - 1} species + background)")
    return class_names


def _load_name_cache() -> dict[str, str]:
    if NAME_CACHE_PATH.exists():
        return json.loads(NAME_CACHE_PATH.read_text())
    return {}


def _save_name_cache(cache: dict[str, str]) -> None:
    NAME_CACHE_PATH.write_text(json.dumps(cache, indent=2, sort_keys=True))


def resolve_common_name(scientific_name: str, cache: dict[str, str]) -> str:
    if scientific_name in cache:
        return cache[scientific_name]
    common_name = scientific_name  # fallback: use the scientific name as-is
    try:
        resp = requests.get(
            f"{INATURALIST_API}/taxa",
            params={"q": scientific_name, "rank": "species,subspecies", "per_page": 1},
            timeout=15,
        )
        resp.raise_for_status()
        results = resp.json().get("results", [])
        if results and results[0].get("preferred_common_name"):
            # iNaturalist already returns correctly-cased names (e.g. "Cassin's
            # Finch") — don't re-titlecase, it mangles apostrophes ("Cassin'S").
            common_name = results[0]["preferred_common_name"]
    except Exception as e:
        print(f"  [name lookup] {scientific_name}: {e} — using scientific name")
    cache[scientific_name] = common_name
    _save_name_cache(cache)
    time.sleep(1)  # be polite to the free iNaturalist API
    return common_name


def resolve_common_names(scientific_names: list[str]) -> list[str]:
    cache = _load_name_cache()
    to_resolve = [n for n in scientific_names if n not in cache and n != BACKGROUND_LABEL]
    if to_resolve:
        print(f"Resolving {len(to_resolve)} common names via iNaturalist "
              f"({len(scientific_names) - len(to_resolve)} already cached)...")
        for name in tqdm(to_resolve, desc="Looking up common names"):
            resolve_common_name(name, cache)
    return [cache.get(n, n) for n in scientific_names]


def convert_to_coreml(savedmodel_dir: Path, class_names: list[str], output_path: str):
    print("Converting to CoreML...")
    # The SavedModel exposes two signatures ("image_classifier" and "default")
    # for the same underlying graph. coremltools' TF2 SavedModel loader only
    # supports a single concrete function, so we load it ourselves and hand
    # coremltools exactly one signature rather than the whole directory.
    loaded = tf.saved_model.load(str(savedmodel_dir))
    concrete_func = loaded.signatures["image_classifier"]

    mlmodel = ct.convert(
        [concrete_func],
        source="tensorflow",
        inputs=[ct.ImageType(
            name="hub_input/images",
            shape=(1, INPUT_SIZE, INPUT_SIZE, 3),
            scale=1.0 / 255.0,   # model expects [0, 1] float input from raw 0-255 pixels
            bias=[0.0, 0.0, 0.0],
            color_layout=ct.colorlayout.RGB,
        )],
        classifier_config=ct.ClassifierConfig(class_names),
        minimum_deployment_target=ct.target.iOS16,
    )
    mlmodel.short_description = (
        f"BirdMap bird species classifier — {MODEL_SOURCE}, {MODEL_LICENSE}, used as-is (not fine-tuned)."
    )
    mlmodel.save(output_path)
    print(f"  Saved {output_path}")


def zip_model(model_path: str, zip_out: Path) -> None:
    with zipfile.ZipFile(zip_out, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in Path(model_path).rglob("*"):
            zf.write(f, f.relative_to(Path(model_path).parent))
    print(f"  Zipped to {zip_out}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="./output",
                        help="Directory to write BirdClassifier.mlpackage.zip + manifest.json to")
    parser.add_argument("--skip-name-resolution", action="store_true",
                        help="Ship scientific names as-is instead of resolving common names")
    args = parser.parse_args()

    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    scientific_names = download_labelmap()
    class_names = scientific_names if args.skip_name_resolution else resolve_common_names(scientific_names)

    with tempfile.TemporaryDirectory() as tmp:
        savedmodel_dir = download_savedmodel(Path(tmp) / "savedmodel")
        model_path = str(Path(tmp) / "BirdClassifier.mlpackage")
        convert_to_coreml(savedmodel_dir, class_names, model_path)

        zip_path = out_dir / "BirdClassifier.mlpackage.zip"
        zip_model(model_path, zip_path)

    version = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d_%H%M%S")
    manifest = {
        "version": version,
        "mediaType": "photo",
        "numClasses": len(class_names),
        "classNames": class_names,
        "source": MODEL_SOURCE,
        "license": MODEL_LICENSE,
        "modelZip": zip_path.name,
    }
    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))
    print(f"  Wrote {manifest_path}")
    print(f"\nDone. Next: in a SEPARATE venv (pip install -r requirements.txt), run:\n"
          f"  python publish_model.py --input {out_dir}")


if __name__ == "__main__":
    main()
