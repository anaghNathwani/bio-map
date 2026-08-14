"""
Publishes a converted model artifact (produced by convert_photo_model.py, or
any script that writes the same manifest.json + zip layout) to Firebase
Storage + the `model_versions` Firestore collection.

Deliberately has NO tensorflow/coremltools dependency — see the comment at
the top of convert_photo_model.py for why this is a separate script/venv.

Usage:
    python publish_model.py --input ./output
    python publish_model.py --input ./output --service-account path/to/key.json
"""

import argparse
import json
from pathlib import Path

from firebase_admin import firestore as fb_firestore

import firestore_client


def upload_and_register(manifest: dict, zip_path: Path, db, bucket):
    version = manifest["version"]
    media_type = manifest["mediaType"]

    storage_path = f"models/birdmap_{media_type}_{version}.mlpackage.zip"
    blob = bucket.blob(storage_path)
    blob.upload_from_filename(str(zip_path), content_type="application/zip")
    print(f"Uploaded model to gs://{bucket.name}/{storage_path}")

    versions_ref = db.collection("model_versions")
    batch = db.batch()
    existing = versions_ref.where("mediaType", "==", media_type).where("isActive", "==", True).stream()
    for doc in existing:
        batch.update(doc.reference, {"isActive": False})
    new_ref = versions_ref.document()
    batch.set(new_ref, {
        "version": version,
        "mediaType": media_type,
        "storagePath": storage_path,
        "numClasses": manifest.get("numClasses"),
        "classNames": manifest.get("classNames"),
        "source": manifest.get("source"),
        "license": manifest.get("license"),
        "isActive": True,
        "createdAt": fb_firestore.SERVER_TIMESTAMP,
    })
    batch.commit()
    print(f"Registered model version {version} ({manifest.get('numClasses')} classes, mediaType={media_type})")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="./output",
                        help="Directory containing manifest.json + the model zip "
                             "(as written by convert_photo_model.py)")
    parser.add_argument("--service-account", default=None,
                        help="Path to a Firebase service account JSON. "
                             "Falls back to GOOGLE_APPLICATION_CREDENTIALS or ADC.")
    args = parser.parse_args()

    in_dir = Path(args.input)
    manifest = json.loads((in_dir / "manifest.json").read_text())
    zip_path = in_dir / manifest["modelZip"]
    if not zip_path.exists():
        raise FileNotFoundError(f"{zip_path} not found — did convert_photo_model.py finish successfully?")

    db = firestore_client.get_db(args.service_account)
    bucket = firestore_client.get_bucket(args.service_account)
    upload_and_register(manifest, zip_path, db, bucket)


if __name__ == "__main__":
    main()
