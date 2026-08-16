"""
BirdMap live poll — run periodically (e.g. via the scheduled GitHub Actions
workflow at .github/workflows/live-poll.yml) rather than as a persistent
process. A persistent listener needs an always-on machine to actually be
"live"; polling on a schedule runs entirely on free, ephemeral CI minutes
instead, at the cost of turning "instant" into "within one poll interval."

Each run does two things once, then exits:

  1. Audio bird-call ID — finds audio sightings with no aiSpeciesSuggestion
     yet, downloads the recording (a plain HTTPS GET — Supabase Storage
     buckets are public for reads, no credentials needed to fetch), analyzes
     it with BirdNET (birdnetlib, Cornell's open-weight bird-call model, used
     as-is — not fine-tuned), and writes the prediction back onto the
     sighting doc.

  2. Annotation moderation — finds annotations with moderation == "pending"
     (set by the app at submission time — see FirebaseService.submitAnnotation
     in the iOS app) and classifies each as a genuine attempt or a
     "shitpost" using a small local open-weight sentence-embedding model (no
     LLM API key, no training from scratch), writing the verdict back.
     Annotations with no species ("unsure") are always "ok" and never touch
     the model.

Usage:
    python live_poll.py
    python live_poll.py --service-account path/to/key.json

Credentials: see firestore_client.py.
"""

import argparse
import logging
import os
import tempfile

import requests
from google.cloud.firestore_v1.base_query import FieldFilter

import firestore_client

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("live_poll")


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


def _process_audio_sighting(db, doc_id: str, data: dict) -> None:
    audio_url = data.get("audioURL")
    if not audio_url:
        logger.warning("  No audioURL for %s, skipping", doc_id)
        return

    logger.info("Analyzing audio sighting %s...", doc_id)
    resp = requests.get(audio_url, timeout=60)
    resp.raise_for_status()

    with tempfile.NamedTemporaryFile(suffix=".m4a", delete=False) as f:
        f.write(resp.content)
        tmp_path = f.name

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


def poll_audio(db) -> int:
    """Process every unanalyzed audio sighting once. Returns count processed."""
    query = db.collection("sightings").where(filter=FieldFilter("mediaType", "==", "audio"))
    processed = 0
    for doc in query.stream():
        data = doc.to_dict() or {}
        if data.get("aiSpeciesSuggestion") is not None:
            continue  # already analyzed
        try:
            _process_audio_sighting(db, doc.id, data)
            processed += 1
        except Exception:
            logger.exception("  Failed processing audio sighting %s", doc.id)
    return processed


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


def poll_moderation(db) -> int:
    """Process every annotation still marked moderation == "pending". Returns count processed."""
    query = db.collection_group("annotations").where(filter=FieldFilter("moderation", "==", "pending"))
    processed = 0
    for doc in query.stream():
        data = doc.to_dict() or {}
        sighting_id = doc.reference.parent.parent.id
        try:
            _process_annotation(db, sighting_id, doc.id, data)
            processed += 1
        except Exception:
            logger.exception("  Failed moderating annotation %s", doc.id)
    return processed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--service-account", default=None,
                        help="Path to a Firebase service account JSON. "
                             "Falls back to GOOGLE_APPLICATION_CREDENTIALS or ADC.")
    args = parser.parse_args()

    db = firestore_client.get_db(args.service_account)

    n_audio = poll_audio(db)
    n_mod = poll_moderation(db)
    logger.info("Done: %d audio sighting(s) analyzed, %d annotation(s) moderated", n_audio, n_mod)


if __name__ == "__main__":
    main()
