import logging
import os
import time
import requests

logger = logging.getLogger(__name__)

INSTAGRAM_USER_ID = os.getenv("INSTAGRAM_USER_ID", "")
INSTAGRAM_ACCESS_TOKEN = os.getenv("INSTAGRAM_ACCESS_TOKEN", "")
GRAPH_URL = "https://graph.instagram.com/v19.0"


def post_sighting(photo_url: str, species: str | None, location: str | None) -> None:
    """Post a new bird sighting to Instagram. No-ops if credentials are missing."""
    if not INSTAGRAM_USER_ID or not INSTAGRAM_ACCESS_TOKEN:
        return

    try:
        parts = [f"🐦 {species}" if species else "🐦 Bird sighting"]
        if location:
            parts.append(f"📍 {location}")
        parts.append("#BirdMap #CitizenScience #Birding #Birds")
        caption = "\n".join(parts)

        r = requests.post(
            f"{GRAPH_URL}/{INSTAGRAM_USER_ID}/media",
            json={
                "image_url": photo_url,
                "caption": caption,
                "access_token": INSTAGRAM_ACCESS_TOKEN,
            },
            timeout=15,
        )
        r.raise_for_status()
        container_id = r.json()["id"]

        # Instagram requires a short pause between container creation and publish
        time.sleep(3)

        requests.post(
            f"{GRAPH_URL}/{INSTAGRAM_USER_ID}/media_publish",
            json={
                "creation_id": container_id,
                "access_token": INSTAGRAM_ACCESS_TOKEN,
            },
            timeout=15,
        ).raise_for_status()

        logger.info("Instagram post published for sighting (species=%s)", species)
    except Exception as e:
        logger.warning("Instagram post failed (non-fatal): %s", e)
