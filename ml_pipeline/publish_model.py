"""
Publishes a converted model artifact (produced by convert_photo_model.py, or
any script that writes the same manifest.json + zip layout) to Supabase
Storage + the `model_versions` Firestore collection.

Why Supabase Storage and not Firebase Storage: Firebase Storage now requires
a linked billing account (Blaze plan) for every project regardless of usage.
Supabase Storage's free tier needs no card at all. Firestore itself stays on
Firebase (unaffected by that policy — only Storage is gated), so this script
still needs Firebase Admin credentials to write the `model_versions` doc; it
just no longer uses Firebase for the blob itself.

Deliberately has NO tensorflow/coremltools dependency — see the comment at
the top of convert_photo_model.py for why this is a separate script/venv.

Usage:
    python publish_model.py --input ./output
    python publish_model.py --input ./output --service-account path/to/key.json

Supabase credentials (env vars, matching backend/.env.example's convention):
    S3_ENDPOINT      e.g. https://<project-ref>.supabase.co/storage/v1/s3
    S3_ACCESS_KEY    the Supabase project ref
    S3_SECRET_KEY    the service_role API key (Project Settings -> API)
    MODEL_BUCKET     default "birdmap-models"
    PUBLIC_S3_URL    e.g. https://<project-ref>.supabase.co/storage/v1
"""

import argparse
import json
import os
from pathlib import Path

import boto3
from firebase_admin import firestore as fb_firestore

import firestore_client


def get_s3_client():
    return boto3.client(
        "s3",
        endpoint_url=os.environ["S3_ENDPOINT"],
        aws_access_key_id=os.environ["S3_ACCESS_KEY"],
        aws_secret_access_key=os.environ["S3_SECRET_KEY"],
        region_name="us-east-1",  # Supabase Storage doesn't use a real AWS region
    )


def upload_and_register(manifest: dict, zip_path: Path, db):
    version = manifest["version"]
    media_type = manifest["mediaType"]
    bucket = os.environ.get("MODEL_BUCKET", "birdmap-models")

    key = f"models/birdmap_{media_type}_{version}.mlpackage.zip"
    s3 = get_s3_client()
    s3.upload_file(str(zip_path), bucket, key, ExtraArgs={"ContentType": "application/zip"})

    public_base = os.environ.get("PUBLIC_S3_URL") or os.environ["S3_ENDPOINT"]
    download_url = f"{public_base}/{bucket}/{key}"
    print(f"Uploaded model to {download_url}")

    versions_ref = db.collection("model_versions")
    batch = db.batch()
    existing = versions_ref.where("mediaType", "==", media_type).where("isActive", "==", True).stream()
    for doc in existing:
        batch.update(doc.reference, {"isActive": False})
    new_ref = versions_ref.document()
    batch.set(new_ref, {
        "version": version,
        "mediaType": media_type,
        "downloadURL": download_url,
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
                        help="Path to a Firebase service account JSON (for Firestore only). "
                             "Falls back to GOOGLE_APPLICATION_CREDENTIALS or ADC.")
    args = parser.parse_args()

    missing = [v for v in ("S3_ENDPOINT", "S3_ACCESS_KEY", "S3_SECRET_KEY") if v not in os.environ]
    if missing:
        raise SystemExit(f"Missing required env var(s): {', '.join(missing)} — see the module docstring.")

    in_dir = Path(args.input)
    manifest = json.loads((in_dir / "manifest.json").read_text())
    zip_path = in_dir / manifest["modelZip"]
    if not zip_path.exists():
        raise FileNotFoundError(f"{zip_path} not found — did convert_photo_model.py finish successfully?")

    db = firestore_client.get_db(args.service_account)
    upload_and_register(manifest, zip_path, db)


if __name__ == "__main__":
    main()
