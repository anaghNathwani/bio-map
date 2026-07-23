import asyncio
import hashlib
import logging
from functools import lru_cache
from typing import Optional

import requests
from fastapi import APIRouter, HTTPException, UploadFile, File, Depends
from app.api.deps import current_user
from app.config import settings

router = APIRouter(prefix="/vision", tags=["vision"])
logger = logging.getLogger(__name__)

_cache: dict[str, list[dict]] = {}
VISION_URL = "https://vision.googleapis.com/v1/images:annotate"


async def _call_vision_api(image_data: bytes) -> list[dict]:
    key = hashlib.md5(image_data).hexdigest()
    if key in _cache:
        return _cache[key]

    results = await asyncio.to_thread(_call_vision_sync, image_data)
    _cache[key] = results
    return results


def _call_vision_sync(image_data: bytes) -> list[dict]:
    if not settings.google_cloud_api_key:
        return []

    import base64
    b64 = base64.b64encode(image_data).decode()

    payload = {
        "requests": [{
            "image": {"content": b64},
            "features": [
                {"type": "LABEL_DETECTION", "maxResults": 10},
                {"type": "WEB_DETECTION", "maxResults": 5},
            ],
        }]
    }
    try:
        r = requests.post(
            VISION_URL,
            params={"key": settings.google_cloud_api_key},
            json=payload,
            timeout=10,
        )
        r.raise_for_status()
        data = r.json()["responses"][0]
    except Exception as e:
        logger.warning("Google Vision API error: %s", e)
        return []

    candidates: dict[str, float] = {}

    for label in data.get("labelAnnotations", []):
        desc = label.get("description", "")
        score = label.get("score", 0.0)
        # Only surface bird-related labels
        if any(word in desc.lower() for word in ("bird", "avian", "sparrow", "robin", "hawk",
                "eagle", "owl", "duck", "heron", "warbler", "finch", "crow", "jay",
                "wren", "vireo", "tanager", "thrush", "flycatcher", "swallow")):
            candidates[desc] = max(candidates.get(desc, 0), score)

    for entity in data.get("webDetection", {}).get("webEntities", []):
        desc = entity.get("description", "")
        score = entity.get("score", 0.0)
        if desc and score > 0.3:
            candidates[desc] = max(candidates.get(desc, 0), score)

    return sorted(
        [{"species": k, "confidence": round(v, 3)} for k, v in candidates.items()],
        key=lambda x: x["confidence"],
        reverse=True,
    )[:5]


@router.post("/identify")
async def identify_image(
    photo: UploadFile = File(...),
    _user=Depends(current_user),
):
    data = await photo.read(10 * 1024 * 1024)
    if not data:
        raise HTTPException(400, "Empty file")

    candidates = await _call_vision_api(data)
    return {"candidates": candidates}
