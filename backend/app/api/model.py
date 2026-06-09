from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.database import get_db
from app.models.annotation import ModelVersion
from app.services.storage import get_model_download_url

router = APIRouter(prefix="/model", tags=["model"])


class RegisterModelRequest(BaseModel):
    version: str
    s3_key: str
    num_classes: int
    accuracy: Optional[float] = None
    class_names: list[str] = []


@router.get("/version")
async def model_version(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(ModelVersion)
        .where(ModelVersion.is_active == True)  # noqa: E712
        .order_by(ModelVersion.created_at.desc())
        .limit(1)
    )
    mv = result.scalar_one_or_none()
    if not mv:
        raise HTTPException(status_code=404, detail="No model available yet")
    return {
        "version": mv.version,
        "num_classes": mv.num_classes,
        "accuracy": mv.accuracy,
        "created_at": mv.created_at.isoformat(),
    }


@router.get("/download")
async def model_download(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(ModelVersion)
        .where(ModelVersion.is_active == True)  # noqa: E712
        .order_by(ModelVersion.created_at.desc())
        .limit(1)
    )
    mv = result.scalar_one_or_none()
    if not mv:
        raise HTTPException(status_code=404, detail="No model available yet")
    url = get_model_download_url(mv.s3_key)
    return {"url": url, "version": mv.version}


@router.post("/register", status_code=201)
async def register_model(body: RegisterModelRequest, db: AsyncSession = Depends(get_db)):
    # Deactivate all previous versions
    existing = await db.execute(select(ModelVersion).where(ModelVersion.is_active == True))  # noqa: E712
    for mv in existing.scalars().all():
        mv.is_active = False

    new_mv = ModelVersion(
        version=body.version,
        s3_key=body.s3_key,
        num_classes=body.num_classes,
        accuracy=body.accuracy,
        is_active=True,
    )
    db.add(new_mv)
    await db.commit()
    return {"version": body.version}
