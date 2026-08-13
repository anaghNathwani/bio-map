"""
BirdMap live service — self-hosted, run continuously from Terminal.

Runs two Firestore realtime listeners (push-based watches, not polling):

  1. Audio bird-call ID — analyzes newly uploaded audio sightings with
     BirdNET (birdnetlib, Cornell's open-weight bird-call model, used as-is
     — not fine-tuned in this pass) and writes the prediction back onto the
     sighting doc, the same fields the on-device photo classifier fills in.

  2. Annotation moderation — classifies each new community annotation as a
     genuine attempt or a "shitpost" using a small local open-weight
     sentence-embedding model (no LLM API key, no training from scratch),
     and writes the verdict back onto the annotation doc. Annotations with
     no species ("unsure") are always "ok" and never touch the model.

Usage:
    python live_service.py
    python live_service.py --service-account path/to/key.json

Credentials: see firestore_client.py.

Quick note: This is off-loaded to the firebase client, and not run locally on a user's device.
"""

import argparse
import logging
import os
import tempfile
import time

from google.cloud.firestore_v1.base_query import FieldFilter

import firestore_client

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("live_service")


# ─────────────────────────────────────────────────────────────────────────
# Audio: BirdNET (ported from backend/app/services/birdnet.py)
# ─────────────────────────────────────────────────────────────────────────

def _run_birdnet(audio_path: str, lat: float | None, lng: float | None) -> list[dict]:
    from birdnetlib import Recording
    from birdnetlib.analyzer import Analyzer

    analyzer = Analyzer()
    recording = Recording(analyzer, audio_path, lat=lat, lon=lng, min_conf=0.1)
    recording.analyze()
    results = recording.detections or []
    seen: dict[str, float] = {}
    for r in results:
        name = r.get("common_name") or r.get("scientific_name", "Unknown")
        conf = float(r.get("confidence", 0))
        if name not in seen or conf > seen[name]:
            seen[name] = conf
    return sorted(
        [{"species": k, "confidence": v} for k, v in seen.items()],
        key=lambda x: x["confidence"], reverse=True,
    )[:3]


def _process_audio_sighting(db, bucket, doc_id: str, data: dict) -> None:
    logger.info("Analyzing audio sighting %s...", doc_id)
    blob = bucket.blob(f"sightings/{doc_id}/audio.m4a")
    if not blob.exists():
        logger.warning("  No audio blob found for %s, skipping", doc_id)
        return

    with tempfile.NamedTemporaryFile(suffix=".m4a", delete=False) as f:
        tmp_path = f.name
        blob.download_to_file(f)

    try:
        detections = _run_birdnet(tmp_path, data.get("latitude"), data.get("longitude"))
    except Exception as e:
        logger.warning("  BirdNET analysis failed for %s: %s", doc_id, e)
        return
    finally:
        os.unlink(tmp_path)

    top = detections[0] if detections else None
    db.collection("sightings").document(doc_id).update({
        "aiSpeciesSuggestion": top["species"] if top else None,
        "aiConfidence": top["confidence"] if top else None,
    })
    logger.info("  %s -> %s", doc_id, top["species"] if top else "no detection")


def _watch_audio(db, bucket):
    query = db.collection("sightings").where(filter=FieldFilter("mediaType", "==", "audio"))

    def on_snapshot(col_snapshot, changes, read_time):
        for change in changes:
            if change.type.name not in ("ADDED", "MODIFIED"):
                continue
            doc = change.document
            data = doc.to_dict() or {}
            if data.get("aiSpeciesSuggestion") is not None:
                continue  # already analyzed
            try:
                _process_audio_sighting(db, bucket, doc.id, data)
            except Exception:
                logger.exception("  Failed processing audio sighting %s", doc.id)

    return query.on_snapshot(on_snapshot)


# ─────────────────────────────────────────────────────────────────────────
# Moderation: local embedding-based shitpost filter
# ─────────────────────────────────────────────────────────────────────────

GENUINE_EXEMPLARS = [
    "American Robin foraging on the lawn, adult plumage",
    "Northern Cardinal singing from a tree branch",
    "A juvenile Red-tailed Hawk perched on a fence post",
    "Blue Jay eating from a bird feeder",
    "Small brown sparrow with a streaked breast, not fully sure of the exact species",
    "Great Blue Heron wading in shallow water hunting for fish",
    "Mallard duck swimming with ducklings",
    "Downy Woodpecker pecking at a dead tree trunk",
    "Possibly a Cooper's Hawk, saw it flying fast through the yard",
    "Dark-eyed Junco, first winter plumage, foraging on the ground",
]

SILLY_EXEMPLARS = [
    "lol idk just some random bird whatever",
    "definitely a dragon, not a bird",
    "asdkjfh aksjdf keyboard mash test",
    "my cat photobombed this picture",
    "test test test 123",
    "this bird is literally Batman",
    "no bird here just vibes",
    "aaaaaaaaaaaaaaaaaaaa",
    "haha funny bird go brrrr",
    "im just trolling ignore this",
]

# How much the "silly" similarity must beat "genuine" similarity to flag —
# a small positive margin, since exemplar sets are short and scores are noisy.
FLAG_THRESHOLD = 0.05

_embedder = None
_genuine_emb = None
_silly_emb = None


def _load_moderation_model():
    global _embedder, _genuine_emb, _silly_emb
    if _embedder is not None:
        return
    logger.info("Loading local sentence-embedding model (all-MiniLM-L6-v2)...")
    from sentence_transformers import SentenceTransformer
    _embedder = SentenceTransformer("all-MiniLM-L6-v2")
    _genuine_emb = _embedder.encode(GENUINE_EXEMPLARS, convert_to_tensor=True, normalize_embeddings=True)
    _silly_emb = _embedder.encode(SILLY_EXEMPLARS, convert_to_tensor=True, normalize_embeddings=True)
    logger.info("Moderation model ready.")


def _classify_annotation_text(text: str) -> tuple[str, float]:
    from sentence_transformers import util
    _load_moderation_model()
    text_emb = _embedder.encode(text, convert_to_tensor=True, normalize_embeddings=True)
    genuine_score = util.cos_sim(text_emb, _genuine_emb).max().item()
    silly_score = util.cos_sim(text_emb, _silly_emb).max().item()
    margin = silly_score - genuine_score
    verdict = "flagged" if margin > FLAG_THRESHOLD else "ok"
    return verdict, margin


def _process_annotation(db, sighting_id: str, ann_id: str, data: dict) -> None:
    species = (data.get("species") or "").strip()
    review = data.get("reviewOfAI")

    # No species / "unsure" is always fine per product rule — never a
    # shitpost, and it skips the model entirely (cheap, and correct).
    if not species or review == "unsure":
        verdict, score = "ok", 0.0
    else:
        text_parts = [species, data.get("behavior") or "", data.get("agePlumage") or ""]
        text = " — ".join(p for p in text_parts if p)
        verdict, score = _classify_annotation_text(text)

    db.collection("sightings").document(sighting_id) \
        .collection("annotations").document(ann_id) \
        .update({"moderation": verdict, "moderationScore": score})
    logger.info("  annotation %s/%s -> %s (%.2f)", sighting_id, ann_id, verdict, score)


def _watch_moderation(db):
    query = db.collection_group("annotations")

    def on_snapshot(col_snapshot, changes, read_time):
        for change in changes:
            if change.type.name != "ADDED":
                continue
            doc = change.document
            data = doc.to_dict() or {}
            if data.get("moderation") is not None:
                continue  # already moderated
            sighting_id = doc.reference.parent.parent.id
            try:
                _process_annotation(db, sighting_id, doc.id, data)
            except Exception:
                logger.exception("  Failed moderating annotation %s", doc.id)

    return query.on_snapshot(on_snapshot)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--service-account", default=None,
                        help="Path to a Firebase service account JSON. "
                             "Falls back to GOOGLE_APPLICATION_CREDENTIALS or ADC.")
    args = parser.parse_args()

    db = firestore_client.get_db(args.service_account)
    bucket = firestore_client.get_bucket(args.service_account)

    logger.info("Starting audio + moderation live listeners (Ctrl+C to stop)...")
    audio_watch = _watch_audio(db, bucket)
    moderation_watch = _watch_moderation(db)

    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        logger.info("Stopping...")
        audio_watch.unsubscribe()
        moderation_watch.unsubscribe()


if __name__ == "__main__":
    main()
