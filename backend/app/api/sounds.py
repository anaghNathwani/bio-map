import asyncio
import logging
import uuid
from typing import Optional, Annotated

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, BackgroundTasks
from geoalchemy2.functions import ST_MakePoint, ST_SetSRID
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.sighting import Sighting
from app.models.user import User
from app.api.deps import current_user
from app.services import birdnet
from app.services.storage import upload_audio

router = APIRouter(prefix="/sounds", tags=["sounds"])
logger = logging.getLogger(__name__)

ALLOWED_AUDIO_TYPES = {"audio/m4a", "audio/mp4", "audio/mpeg", "audio/wav",
                       "audio/x-m4a", "audio/aac", "audio/ogg"}
MAX_AUDIO_BYTES = 20 * 1024 * 1024  # 20 MB


@router.post("", status_code=201)
async def upload_sound(
    latitude: Annotated[float, Form(ge=-90, le=90)],
    longitude: Annotated[float, Form(ge=-180, le=180)],
    notes: Annotated[Optional[str], Form(max_length=2000)] = None,
    audio: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
    background_tasks: BackgroundTasks = BackgroundTasks(),
):
    data = await audio.read(MAX_AUDIO_BYTES + 1)
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(413, "Audio file exceeds 20 MB limit")

    try:
        audio_url = await asyncio.to_thread(upload_audio, data, audio.filename or "sound.m4a")
    except Exception as e:
        logger.error("Audio upload failed: %s", e)
        raise HTTPException(502, "Audio storage unavailable, please try again")

    # Run BirdNET identification
    detections = await birdnet.identify_bird_sound(data, lat=latitude, lng=longitude)
    top = detections[0] if detections else None

    sighting = Sighting(
        user_id=user.id,
        photo_url="",
        audio_url=audio_url,
        media_type="audio",
        latitude=latitude,
        longitude=longitude,
        location=ST_SetSRID(ST_MakePoint(longitude, latitude), 4326),
        notes=notes,
        ai_species_suggestion=top["species"] if top else None,
        ai_confidence=top["confidence"] if top else None,
    )
    db.add(sighting)
    await db.commit()
    await db.refresh(sighting)

    logger.info("Sound sighting created: %s by user %s", sighting.id, user.id)
    return {
        "id": str(sighting.id),
        "audio_url": audio_url,
        "ai_species_suggestion": sighting.ai_species_suggestion,
        "ai_confidence": sighting.ai_confidence,
        "candidates": detections,
    }
