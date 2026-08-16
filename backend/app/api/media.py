"""
Media upload broker: verifies the caller's Firebase ID token (the live app's
real auth system) and uploads sighting photos/audio to Supabase Storage on
their behalf. This is the ONLY bridge between the live Firebase/Firestore
app and this backend — everything else here (auth.py, sightings.py,
annotations.py, leaderboard.py, model.py) is a separate, independent system
with its own Postgres-backed users/data, kept for its own sake but not used
by the live app.

Why this exists: Firebase Storage now requires a linked billing account
(Blaze plan) for all projects regardless of usage. Supabase Storage's free
tier needs no card, but (unlike Firebase Storage) has no built-in way to
authorize a per-end-user Firebase-issued token against its buckets, so
uploads are proxied through here instead, using a Supabase service-role key
kept server-side only (never sent to the client). Downloads stay direct —
the bucket is public for reads, so the returned URLs are used as-is by the
app with no further backend involvement.
"""
import asyncio
import logging

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.services.firebase_auth import firebase_user_id
from app.services.storage import upload_sighting_audio, upload_sighting_photo

router = APIRouter(prefix="/media", tags=["media"])
logger = logging.getLogger(__name__)

MAX_PHOTO_BYTES = 20 * 1024 * 1024
MAX_AUDIO_BYTES = 20 * 1024 * 1024
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/heic", "image/heif"}
ALLOWED_AUDIO_TYPES = {"audio/m4a", "audio/mp4", "audio/x-m4a", "audio/aac"}


@router.post("/sightings/{sighting_id}/photo")
async def upload_photo_endpoint(
    sighting_id: str,
    photo: UploadFile = File(...),
    uid: str = Depends(firebase_user_id),
):
    content_type = photo.content_type or "image/jpeg"
    if content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail=f"Unsupported image type: {content_type}")

    data = await photo.read(MAX_PHOTO_BYTES + 1)
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=413, detail="Photo exceeds 20 MB limit")

    try:
        photo_url, thumbnail_url = await asyncio.to_thread(upload_sighting_photo, data, sighting_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=f"Invalid image: {e}")
    except Exception as e:
        logger.error("Photo upload failed for sighting %s: %s", sighting_id, e)
        raise HTTPException(status_code=502, detail="Photo storage unavailable, please try again")

    logger.info("Uploaded photo for sighting %s (uid=%s)", sighting_id, uid)
    return {"photoURL": photo_url, "thumbnailURL": thumbnail_url}


@router.post("/sightings/{sighting_id}/audio")
async def upload_audio_endpoint(
    sighting_id: str,
    audio: UploadFile = File(...),
    uid: str = Depends(firebase_user_id),
):
    content_type = audio.content_type or "audio/mp4"
    if content_type not in ALLOWED_AUDIO_TYPES:
        raise HTTPException(status_code=415, detail=f"Unsupported audio type: {content_type}")

    data = await audio.read(MAX_AUDIO_BYTES + 1)
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="Audio exceeds 20 MB limit")

    try:
        audio_url = await asyncio.to_thread(upload_sighting_audio, data, sighting_id)
    except Exception as e:
        logger.error("Audio upload failed for sighting %s: %s", sighting_id, e)
        raise HTTPException(status_code=502, detail="Audio storage unavailable, please try again")

    logger.info("Uploaded audio for sighting %s (uid=%s)", sighting_id, uid)
    return {"audioURL": audio_url}
