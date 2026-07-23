import logging
import time
import urllib.parse
from typing import Optional

import requests
from fastapi import APIRouter, Query
from app.config import settings

router = APIRouter(prefix="/birds", tags=["birds"])
logger = logging.getLogger(__name__)

# Simple TTL cache: {species: (timestamp, data)}
_cache: dict[str, tuple[float, dict]] = {}
CACHE_TTL = 86400  # 24 hours


def _cached(species: str) -> Optional[dict]:
    entry = _cache.get(species)
    if entry and (time.time() - entry[0]) < CACHE_TTL:
        return entry[1]
    return None


def _store(species: str, data: dict) -> None:
    _cache[species] = (time.time(), data)


def _fetch_wikipedia(species: str) -> dict:
    encoded = urllib.parse.quote(species.replace(" ", "_"))
    try:
        r = requests.get(
            f"https://en.wikipedia.org/api/rest_v1/page/summary/{encoded}",
            headers={"User-Agent": "BirdMapApp/1.0"},
            timeout=8,
        )
        if r.status_code == 200:
            d = r.json()
            return {
                "description": d.get("extract", ""),
                "image_url": d.get("thumbnail", {}).get("source"),
                "wiki_url": d.get("content_urls", {}).get("mobile", {}).get("page")
                    or d.get("content_urls", {}).get("desktop", {}).get("page", ""),
            }
    except Exception as e:
        logger.warning("Wikipedia fetch failed for %s: %s", species, e)
    return {"description": "", "image_url": None, "wiki_url": ""}


def _fetch_ebird(species: str) -> dict:
    if not settings.ebird_api_key:
        return {}
    encoded = urllib.parse.quote(species)
    try:
        r = requests.get(
            f"https://api.ebird.org/v2/ref/taxonomy/ebird?fmt=json&q={encoded}",
            headers={"X-eBirdApiToken": settings.ebird_api_key},
            timeout=8,
        )
        if r.status_code == 200 and r.json():
            d = r.json()[0]
            return {
                "scientific_name": d.get("sciName", ""),
                "family": d.get("familyComName", ""),
                "order": d.get("order", ""),
                "species_code": d.get("speciesCode", ""),
            }
    except Exception as e:
        logger.warning("eBird fetch failed for %s: %s", species, e)
    return {}


@router.get("/info")
async def bird_info(species: str = Query(..., min_length=2, max_length=100)):
    cached = _cached(species)
    if cached:
        return cached

    wiki = _fetch_wikipedia(species)
    ebird = _fetch_ebird(species)

    species_slug = species.replace(" ", "_")
    ebird_code = ebird.get("species_code", "")
    allaboutbirds_url = (
        f"https://www.allaboutbirds.org/guide/{species_slug}"
        if species_slug else ""
    )
    ebird_url = (
        f"https://ebird.org/species/{ebird_code}"
        if ebird_code else f"https://ebird.org/search?q={urllib.parse.quote(species)}"
    )

    result = {
        "species": species,
        "description": wiki.get("description", ""),
        "image_url": wiki.get("image_url"),
        "wiki_url": wiki.get("wiki_url", ""),
        "ebird_url": ebird_url,
        "allaboutbirds_url": allaboutbirds_url,
        "scientific_name": ebird.get("scientific_name", ""),
        "family": ebird.get("family", ""),
        "order": ebird.get("order", ""),
    }

    _store(species, result)
    return result
