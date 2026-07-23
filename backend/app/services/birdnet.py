import asyncio
import logging
import os
import tempfile
from typing import Optional

logger = logging.getLogger(__name__)


async def identify_bird_sound(
    audio_data: bytes,
    lat: Optional[float] = None,
    lng: Optional[float] = None,
) -> list[dict]:
    """Run BirdNET analysis on audio bytes. Returns list of {species, confidence}."""
    try:
        return await asyncio.to_thread(_run_birdnet, audio_data, lat, lng)
    except Exception as e:
        logger.warning("BirdNET analysis failed: %s", e)
        return []


def _run_birdnet(audio_data: bytes, lat: Optional[float], lng: Optional[float]) -> list[dict]:
    try:
        from birdnetlib import Recording
        from birdnetlib.analyzer import Analyzer
    except ImportError:
        logger.warning("birdnetlib not installed — audio ID unavailable")
        return []

    with tempfile.NamedTemporaryFile(suffix=".m4a", delete=False) as f:
        f.write(audio_data)
        tmp_path = f.name

    try:
        analyzer = Analyzer()
        recording = Recording(
            analyzer,
            tmp_path,
            lat=lat,
            lon=lng,
            min_conf=0.1,
        )
        recording.analyze()
        results = recording.detections or []
        seen: dict[str, float] = {}
        for r in results:
            name = r.get("common_name") or r.get("scientific_name", "Unknown")
            conf = float(r.get("confidence", 0))
            if name not in seen or conf > seen[name]:
                seen[name] = conf
        return sorted(
            [{"species": k, "confidence": v} for k, v in seen.items()],
            key=lambda x: x["confidence"],
            reverse=True,
        )[:3]
    finally:
        os.unlink(tmp_path)
