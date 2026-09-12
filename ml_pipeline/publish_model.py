"""
Publishes a converted model artifact (produced by convert_photo_model.py, or
any script that writes the same manifest.json + zip layout) with Firestore as
the primary store and Supabase Storage as a redundant fallback copy.

Firebase Storage would need a linked billing account (Blaze plan) for any
usage regardless of volume; Firestore itself is unaffected by that and has
never needed billing. A model file is too large for one Firestore document
(1 MiB cap), so it's split into base64-encoded chunks and written as a
subcollection under its model_versions doc — the same "compress client-side
and embed as base64, skip Storage entirely" idea already used for sighting
photo/audio (FirebaseService.uploadImage/uploadAudio), just chunked because a
~15MB model doesn't fit in a single 1 MiB document the way a compressed photo
does. See github.com/ishanvi-dekate/team-efficient-epp for the pattern this
followed (Profile.jsx's avatar upload, ChatBot.jsx's imageToBase64).

On top of that primary path, the raw zip is also uploaded to Supabase Storage
(free tier, no card) and its public URL is stored as `fallbackURL` on the
model_versions doc, so a client that can't reach Firestore chunks for any
reason still has somewhere to download the model from. The Supabase upload is
best-effort: if its env vars aren't set or the upload fails, the script warns
and still leaves the Firestore write (primary) intact rather than failing the
whole publish.

Deliberately has NO tensorflow/coremltools dependency — see the comment at
the top of convert_photo_model.py for why this is a separate script/venv.

Usage:
    python publish_model.py --input ./output
    python publish_model.py --input ./output --service-account path/to/key.json

Supabase fallback env vars (all optional — omit any to skip the fallback):
    S3_ENDPOINT      e.g. https://<project-ref>.storage.supabase.co/storage/v1/s3
    S3_ACCESS_KEY    an S3 access key generated under Storage -> S3 Connection
    S3_SECRET_KEY    its matching secret
    SUPABASE_URL     e.g. https://<project-ref>.supabase.co (for the public URL)
    MODEL_BUCKET     default "birdmap-models" — must be a public bucket
"""

import argparse
import base64
import json
import os
from pathlib import Path

from firebase_admin import firestore as fb_firestore

import firestore_client

# Comfortably under Firestore's 1 MiB per-document cap after base64's ~4/3
# inflation (650_000 raw bytes -> ~867_000 base64 chars), leaving headroom
# for the chunk document's other fields.
CHUNK_SIZE = 650_000


def upload_fallback_copy(zip_path: Path, media_type: str, version: str) -> str | None:
    """Best-effort upload of the raw zip to Supabase Storage. Returns the
    public download URL, or None if skipped/failed (never raises)."""
    required = ("S3_ENDPOINT", "S3_ACCESS_KEY", "S3_SECRET_KEY", "SUPABASE_URL")
    missing = [v for v in required if v not in os.environ]
    if missing:
        print(f"Skipping Supabase fallback upload — missing env var(s): {', '.join(missing)}")
        return None

    try:
        import boto3
    except ImportError:
        print("Skipping Supabase fallback upload — boto3 not installed (pip install boto3)")
        return None

    bucket = os.environ.get("MODEL_BUCKET", "birdmap-models")
    key = f"models/birdmap_{media_type}_{version}.mlpackage.zip"
    try:
        s3 = boto3.client(
            "s3",
            endpoint_url=os.environ["S3_ENDPOINT"],
            aws_access_key_id=os.environ["S3_ACCESS_KEY"],
            aws_secret_access_key=os.environ["S3_SECRET_KEY"],
            region_name="us-east-1",  # Supabase Storage doesn't use a real AWS region
        )
        s3.upload_file(str(zip_path), bucket, key, ExtraArgs={"ContentType": "application/zip"})
        # Supabase serves public objects under /storage/v1/object/public/{bucket}/{key}
        # — the bucket must be marked public or this URL 404s.
        download_url = f"{os.environ['SUPABASE_URL']}/storage/v1/object/public/{bucket}/{key}"
        print(f"Uploaded fallback copy to {download_url}")
        return download_url
    except Exception as e:  # best-effort — never let the fallback break the primary publish
        print(f"Supabase fallback upload failed (continuing without it): {e}")
        return None


def upload_and_register(manifest: dict, zip_path: Path, db):
    version = manifest["version"]
    media_type = manifest["mediaType"]
    raw = zip_path.read_bytes()

    versions_ref = db.collection("model_versions")
    new_ref = versions_ref.document()
    chunks_ref = new_ref.collection("chunks")

    chunk_count = (len(raw) + CHUNK_SIZE - 1) // CHUNK_SIZE
    print(f"Uploading {len(raw):,} bytes as {chunk_count} chunk document(s)...")
    for i in range(chunk_count):
        raw_chunk = raw[i * CHUNK_SIZE:(i + 1) * CHUNK_SIZE]
        chunks_ref.document(str(i)).set({
            "index": i,
            "data": base64.b64encode(raw_chunk).decode("ascii"),
        })
        print(f"  chunk {i + 1}/{chunk_count}")

    fallback_url = upload_fallback_copy(zip_path, media_type, version)

    batch = db.batch()
    existing = versions_ref.where("mediaType", "==", media_type).where("isActive", "==", True).stream()
    for doc in existing:
        batch.update(doc.reference, {"isActive": False})
    doc_data = {
        "version": version,
        "mediaType": media_type,
        "chunkCount": chunk_count,
        "totalBytes": len(raw),
        "numClasses": manifest.get("numClasses"),
        "classNames": manifest.get("classNames"),
        "source": manifest.get("source"),
        "license": manifest.get("license"),
        "isActive": True,
        "createdAt": fb_firestore.SERVER_TIMESTAMP,
    }
    if fallback_url:
        doc_data["fallbackURL"] = fallback_url
    batch.set(new_ref, doc_data)
    batch.commit()
    print(f"Registered model version {version} ({manifest.get('numClasses')} classes, "
          f"mediaType={media_type}, {chunk_count} chunks"
          f"{', with Supabase fallback' if fallback_url else ''})")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="./output",
                        help="Directory containing manifest.json + the model zip "
                             "(as written by convert_photo_model.py)")
    parser.add_argument("--service-account", default=None,
                        help="Path to a Firebase service account JSON. Falls back to "
                             "GOOGLE_APPLICATION_CREDENTIALS or ADC.")
    args = parser.parse_args()

    in_dir = Path(args.input)
    manifest = json.loads((in_dir / "manifest.json").read_text())
    zip_path = in_dir / manifest["modelZip"]
    if not zip_path.exists():
        raise FileNotFoundError(f"{zip_path} not found — did convert_photo_model.py finish successfully?")

    db = firestore_client.get_db(args.service_account)
    upload_and_register(manifest, zip_path, db)


if __name__ == "__main__":
    main()
