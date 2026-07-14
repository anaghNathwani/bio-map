import logging
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.config import settings
from app.database import get_db
from app.models.annotation import ModelVersion
from app.services.storage import get_model_download_url

router = APIRouter(prefix="/model", tags=["model"])
logger = logging.getLogger(__name__)


class RegisterModelRequest(BaseModel):
    version: str
    s3_key: str
    num_classes: int
    accuracy: Optional[float] = None
    class_names: list[str] = []


def _require_model_secret(x_model_secret: str = Header(..., alias="X-Model-Secret")) -> None:
    if x_model_secret != settings.model_register_secret:
        raise HTTPException(status_code=403, detail="Invalid model registration secret")


@router.get("/version")
async def model_version(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(ModelVersion)
        .where(ModelVersion.is_active .is_(True))
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
        .where(ModelVersion.is_active .is_(True))
        .order_by(ModelVersion.created_at.desc())
        .limit(1)
    )
    mv = result.scalar_one_or_none()
    if not mv:
        raise HTTPException(status_code=404, detail="No model available yet")
    url = get_model_download_url(mv.s3_key)
    return {"url": url, "version": mv.version}


@router.post("/register", status_code=201, dependencies=[Depends(_require_model_secret)])
async def register_model(body: RegisterModelRequest, db: AsyncSession = Depends(get_db)):
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
    logger.info("New model version registered: %s (%d classes, %.3f acc)", body.version, body.num_classes, body.accuracy or 0)
    return {"version": body.version}
