import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from geoalchemy2.functions import ST_MakePoint, ST_SetSRID, ST_Within, ST_MakeEnvelope
from pydantic import BaseModel

from app.database import get_db
from app.models.sighting import Sighting
from app.models.annotation import Annotation
from app.models.user import User
from app.api.deps import current_user
from app.services.storage import upload_photo

router = APIRouter(prefix="/sightings", tags=["sightings"])


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
    latitude: float = Form(...),
    longitude: float = Form(...),
    notes: Optional[str] = Form(None),
    photo: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    data = await photo.read()
    photo_url, thumbnail_url = upload_photo(data, photo.content_type or "image/jpeg")

    sighting = Sighting(
        user_id=user.id,
        photo_url=photo_url,
        thumbnail_url=thumbnail_url,
        latitude=latitude,
        longitude=longitude,
        location=ST_SetSRID(ST_MakePoint(longitude, latitude), 4326),
        notes=notes,
    )
    db.add(sighting)
    await db.commit()
    await db.refresh(sighting)
    return {"id": str(sighting.id), "photo_url": photo_url, "thumbnail_url": thumbnail_url}


@router.get("")
async def list_sightings(
    min_lat: Optional[float] = None,
    max_lat: Optional[float] = None,
    min_lng: Optional[float] = None,
    max_lng: Optional[float] = None,
    limit: int = 200,
    db: AsyncSession = Depends(get_db),
):
    q = select(Sighting)
    if all(v is not None for v in [min_lat, max_lat, min_lng, max_lng]):
        envelope = ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326)
        q = q.where(ST_Within(Sighting.location, envelope))
    q = q.order_by(Sighting.created_at.desc()).limit(limit)
    result = await db.execute(q)
    sightings = result.scalars().all()

    out = []
    for s in sightings:
        ann_result = await db.execute(
            select(func.count()).where(Annotation.sighting_id == s.id)
        )
        count = ann_result.scalar()
        top = await db.execute(
            select(Annotation.species, func.count(Annotation.species).label("n"))
            .where(Annotation.sighting_id == s.id)
            .group_by(Annotation.species)
            .order_by(func.count(Annotation.species).desc())
            .limit(1)
        )
        top_row = top.first()
        out.append({
            "id": str(s.id),
            "latitude": s.latitude,
            "longitude": s.longitude,
            "thumbnail_url": s.thumbnail_url,
            "photo_url": s.photo_url,
            "notes": s.notes,
            "ai_species_suggestion": s.ai_species_suggestion,
            "ai_confidence": s.ai_confidence,
            "annotation_count": count,
            "top_species": top_row[0] if top_row else None,
        })
    return out


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
        "notes": s.notes,
        "ai_species_suggestion": s.ai_species_suggestion,
        "ai_confidence": s.ai_confidence,
        "annotations": annotations,
    }
