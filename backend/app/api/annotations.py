import logging
import uuid
from typing import Optional, Annotated
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from pydantic import BaseModel, field_validator

from app.database import get_db
from app.models.sighting import Sighting
from app.models.annotation import Annotation
from app.models.user import User
from app.api.deps import current_user

router = APIRouter(prefix="/sightings", tags=["annotations"])
logger = logging.getLogger(__name__)


class AnnotationRequest(BaseModel):
    species: str
    confidence: float = 1.0
    behavior: Optional[str] = None
    age_plumage: Optional[str] = None

    @field_validator("species")
    @classmethod
    def species_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Species cannot be empty")
        if len(v) > 255:
            raise ValueError("Species name too long")
        return v

    @field_validator("confidence")
    @classmethod
    def confidence_in_range(cls, v: float) -> float:
        if not (0.0 <= v <= 1.0):
            raise ValueError("Confidence must be between 0.0 and 1.0")
        return v

    @field_validator("behavior")
    @classmethod
    def behavior_length(cls, v: Optional[str]) -> Optional[str]:
        if v and len(v) > 255:
            raise ValueError("Behavior value too long")
        return v


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

    await db.execute(
        update(User)
        .where(User.id == user.id)
        .values(annotation_count=User.annotation_count + 1)
    )

    await db.commit()
    await db.refresh(annotation)
    logger.info("Annotation submitted: sighting=%s user=%s species=%s", sighting_id, user.id, body.species)
    return {"id": str(annotation.id)}
