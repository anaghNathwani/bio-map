import asyncio
import logging
import uuid
from typing import Optional, Annotated
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, UploadFile, File, Form, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from geoalchemy2.functions import ST_MakePoint, ST_SetSRID, ST_Within, ST_MakeEnvelope
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.config import settings
from app.database import get_db
from app.models.sighting import Sighting
from app.models.annotation import Annotation
from app.models.user import User
from app.api.deps import current_user
from app.services.storage import upload_photo
from app.services import instagram

router = APIRouter(prefix="/sightings", tags=["sightings"])
limiter = Limiter(key_func=get_remote_address)
logger = logging.getLogger(__name__)

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/heic", "image/heif"}


class AnnotationOut(BaseModel):
    id: uuid.UUID
    species: str
    confidence: float
    behavior: Optional[str]
    age_plumage: Optional[str]
    username: str

    class Config:
        from_attributes = True


class SightingOut(BaseModel):
    id: uuid.UUID
    latitude: float
    longitude: float
    photo_url: str
    thumbnail_url: Optional[str]
    notes: Optional[str]
    ai_species_suggestion: Optional[str]
    ai_confidence: Optional[float]
    annotation_count: int
    top_species: Optional[str]

    class Config:
        from_attributes = True


@router.post("", status_code=201)
async def create_sighting(
    latitude: Annotated[float, Form(ge=-90, le=90)],
    longitude: Annotated[float, Form(ge=-180, le=180)],
    notes: Annotated[Optional[str], Form(max_length=2000)] = None,
    ai_species: Annotated[Optional[str], Form(max_length=255)] = None,
    ai_confidence: Annotated[Optional[float], Form(ge=0, le=1)] = None,
    photo: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
    background_tasks: BackgroundTasks = BackgroundTasks(),
):
    content_type = photo.content_type or "image/jpeg"
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(status_code=415, detail=f"Unsupported image type: {content_type}")

    data = await photo.read(settings.max_photo_bytes + 1)
    if len(data) > settings.max_photo_bytes:
        raise HTTPException(status_code=413, detail=f"Photo exceeds {settings.max_photo_bytes // (1024*1024)} MB limit")

    try:
        photo_url, thumbnail_url = await asyncio.to_thread(upload_photo, data, content_type)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=f"Invalid image: {e}")
    except Exception as e:
        logger.error("Photo upload failed: %s", e)
        raise HTTPException(status_code=502, detail="Photo storage unavailable, please try again")

    sighting = Sighting(
        user_id=user.id,
        photo_url=photo_url,
        thumbnail_url=thumbnail_url,
        media_type="photo",
        latitude=latitude,
        longitude=longitude,
        location=ST_SetSRID(ST_MakePoint(longitude, latitude), 4326),
        notes=notes,
        ai_species_suggestion=ai_species,
        ai_confidence=ai_confidence,
    )
    db.add(sighting)
    await db.commit()
    await db.refresh(sighting)
    logger.info("Sighting created: %s by user %s", sighting.id, user.id)

    background_tasks.add_task(
        instagram.post_sighting,
        photo_url,
        ai_species,
        f"{latitude:.4f}, {longitude:.4f}",
    )

    return {"id": str(sighting.id), "photo_url": photo_url, "thumbnail_url": thumbnail_url}


@router.get("")
@limiter.limit("60/minute")
async def list_sightings(
    request: Request,
    min_lat: Optional[float] = Query(None, ge=-90, le=90),
    max_lat: Optional[float] = Query(None, ge=-90, le=90),
    min_lng: Optional[float] = Query(None, ge=-180, le=180),
    max_lng: Optional[float] = Query(None, ge=-180, le=180),
    limit: int = Query(200, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
):
    count_sq = (
        select(Annotation.sighting_id, func.count().label("annotation_count"))
        .group_by(Annotation.sighting_id)
        .subquery()
    )

    species_counts_sq = (
        select(
            Annotation.sighting_id,
            Annotation.species,
            func.count().label("cnt"),
        )
        .group_by(Annotation.sighting_id, Annotation.species)
        .subquery()
    )

    ranked_sq = (
        select(
            species_counts_sq.c.sighting_id,
            species_counts_sq.c.species,
            func.rank().over(
                partition_by=species_counts_sq.c.sighting_id,
                order_by=species_counts_sq.c.cnt.desc(),
            ).label("rnk"),
        )
        .subquery()
    )
    top_sq = (
        select(ranked_sq.c.sighting_id, ranked_sq.c.species)
        .where(ranked_sq.c.rnk == 1)
        .subquery()
    )

    q = (
        select(
            Sighting,
            func.coalesce(count_sq.c.annotation_count, 0).label("annotation_count"),
            top_sq.c.species.label("top_species"),
        )
        .outerjoin(count_sq, count_sq.c.sighting_id == Sighting.id)
        .outerjoin(top_sq, top_sq.c.sighting_id == Sighting.id)
    )

    if all(v is not None for v in [min_lat, max_lat, min_lng, max_lng]):
        envelope = ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326)
        q = q.where(ST_Within(Sighting.location, envelope))

    q = q.order_by(Sighting.created_at.desc()).limit(limit)
    result = await db.execute(q)
    rows = result.all()

    return _rows_to_list(rows)


def _rows_to_list(rows):
    return [
        {
            "id": str(s.id),
            "latitude": s.latitude,
            "longitude": s.longitude,
            "thumbnail_url": s.thumbnail_url,
            "photo_url": s.photo_url,
            "audio_url": s.audio_url,
            "media_type": s.media_type,
            "notes": s.notes,
            "ai_species_suggestion": s.ai_species_suggestion,
            "ai_confidence": s.ai_confidence,
            "annotation_count": annotation_count,
            "top_species": top_species,
        }
        for s, annotation_count, top_species in rows
    ]


@router.get("/public")
@limiter.limit("60/minute")
async def list_sightings_public(
    request: Request,
    min_lat: Optional[float] = Query(None, ge=-90, le=90),
    max_lat: Optional[float] = Query(None, ge=-90, le=90),
    min_lng: Optional[float] = Query(None, ge=-180, le=180),
    max_lng: Optional[float] = Query(None, ge=-180, le=180),
    limit: int = Query(200, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
):
    """Public sightings list — no auth required (for the web map)."""
    count_sq = (
        select(Annotation.sighting_id, func.count().label("annotation_count"))
        .group_by(Annotation.sighting_id)
        .subquery()
    )
    species_counts_sq = (
        select(Annotation.sighting_id, Annotation.species, func.count().label("cnt"))
        .group_by(Annotation.sighting_id, Annotation.species)
        .subquery()
    )
    ranked_sq = (
        select(
            species_counts_sq.c.sighting_id,
            species_counts_sq.c.species,
            func.rank().over(
                partition_by=species_counts_sq.c.sighting_id,
                order_by=species_counts_sq.c.cnt.desc(),
            ).label("rnk"),
        ).subquery()
    )
    top_sq = select(ranked_sq.c.sighting_id, ranked_sq.c.species).where(ranked_sq.c.rnk == 1).subquery()

    q = (
        select(Sighting, func.coalesce(count_sq.c.annotation_count, 0).label("annotation_count"), top_sq.c.species.label("top_species"))
        .outerjoin(count_sq, count_sq.c.sighting_id == Sighting.id)
        .outerjoin(top_sq, top_sq.c.sighting_id == Sighting.id)
    )
    if all(v is not None for v in [min_lat, max_lat, min_lng, max_lng]):
        envelope = ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326)
        q = q.where(ST_Within(Sighting.location, envelope))

    q = q.order_by(Sighting.created_at.desc()).limit(limit)
    rows = (await db.execute(q)).all()
    return _rows_to_list(rows)


@router.get("/{sighting_id}")
async def get_sighting(sighting_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Sighting).where(Sighting.id == sighting_id))
    s = result.scalar_one_or_none()
    if not s:
        raise HTTPException(status_code=404, detail="Not found")

    ann_result = await db.execute(
        select(Annotation, User.username)
        .join(User, Annotation.user_id == User.id)
        .where(Annotation.sighting_id == sighting_id)
        .order_by(Annotation.created_at.desc())
    )
    annotations = [
        {
            "id": str(a.id),
            "species": a.species,
            "confidence": a.confidence,
            "behavior": a.behavior,
            "age_plumage": a.age_plumage,
            "username": username,
        }
        for a, username in ann_result.all()
    ]

    return {
        "id": str(s.id),
        "latitude": s.latitude,
        "longitude": s.longitude,
        "photo_url": s.photo_url,
        "thumbnail_url": s.thumbnail_url,
        "audio_url": s.audio_url,
        "media_type": s.media_type,
        "notes": s.notes,
        "ai_species_suggestion": s.ai_species_suggestion,
        "ai_confidence": s.ai_confidence,
        "annotations": annotations,
    }
