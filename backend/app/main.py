import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from app.api import auth, sightings, annotations, leaderboard, model, vision, birds, sounds, media
from app.config import settings
from app.database import engine
from app.services.storage import ensure_buckets
# Models imported here so they exist in the process even though Alembic
# (not create_all) manages the schema.
from app.models import user, sighting, annotation  # noqa: F401

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("birdmap")

limiter = Limiter(key_func=get_remote_address)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting BioMap API")
    ensure_buckets()
    logger.info("S3 buckets ready")
    yield
    logger.info("Shutting down BioMap API")


app = FastAPI(title="BioMap API", version="1.0.0", lifespan=lifespan)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

cors_origins = [o.strip() for o in settings.cors_origins.split(",")]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

app.include_router(auth.router)
app.include_router(sightings.router)
app.include_router(annotations.router)
app.include_router(leaderboard.router)
app.include_router(model.router)
app.include_router(vision.router)
app.include_router(birds.router)
app.include_router(sounds.router)
app.include_router(media.router)


@app.get("/health")
async def health():
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return {"status": "ok"}
    except Exception as e:
        logger.error("Health check failed: %s", e)
        return JSONResponse(status_code=503, content={"status": "degraded", "detail": "database unreachable"})
