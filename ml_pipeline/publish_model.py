"""
Publishes a converted model artifact (produced by convert_photo_model.py, or
any script that writes the same manifest.json + zip layout) entirely through
Firebase — Firestore only, no Storage, no Supabase, no backend.

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

Deliberately has NO tensorflow/coremltools dependency — see the comment at
the top of convert_photo_model.py for why this is a separate script/venv.

Usage:
    python publish_model.py --input ./output
    python publish_model.py --input ./output --service-account path/to/key.json
"""

import argparse
import base64
import json
from pathlib import Path

from firebase_admin import firestore as fb_firestore

import firestore_client

# Comfortably under Firestore's 1 MiB per-document cap after base64's ~4/3
# inflation (650_000 raw bytes -> ~867_000 base64 chars), leaving headroom
# for the chunk document's other fields.
CHUNK_SIZE = 650_000


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

    batch = db.batch()
    existing = versions_ref.where("mediaType", "==", media_type).where("isActive", "==", True).stream()
    for doc in existing:
        batch.update(doc.reference, {"isActive": False})
    batch.set(new_ref, {
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
    })
    batch.commit()
    print(f"Registered model version {version} ({manifest.get('numClasses')} classes, "
          f"mediaType={media_type}, {chunk_count} chunks)")


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
