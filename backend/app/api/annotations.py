import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.database import get_db
from app.models.sighting import Sighting
from app.models.annotation import Annotation
from app.models.user import User
from app.api.deps import current_user

router = APIRouter(prefix="/sightings", tags=["annotations"])


class AnnotationRequest(BaseModel):
    species: str
    confidence: float = 1.0
    behavior: Optional[str] = None
    age_plumage: Optional[str] = None


@router.post("/{sighting_id}/annotations", status_code=201)
async def submit_annotation(
    sighting_id: uuid.UUID,
    body: AnnotationRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    result = await db.execute(select(Sighting).where(Sighting.id == sighting_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Sighting not found")

    annotation = Annotation(
        sighting_id=sighting_id,
        user_id=user.id,
        species=body.species,
        confidence=body.confidence,
        behavior=body.behavior,
        age_plumage=body.age_plumage,
    )
    db.add(annotation)
    user.annotation_count += 1
    await db.commit()
    await db.refresh(annotation)
    return {"id": str(annotation.id)}
