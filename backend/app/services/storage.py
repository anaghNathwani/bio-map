import io
import uuid
import boto3
from PIL import Image
from app.config import settings

s3 = boto3.client(
    "s3",
    endpoint_url=settings.s3_endpoint or "http://localhost:9000",
    aws_access_key_id=settings.s3_access_key or "minioadmin",
    aws_secret_access_key=settings.s3_secret_key or "minioadmin",
    # Supabase Storage and MinIO both work without a real AWS region
    region_name="us-east-1",
)


SOUNDS_BUCKET = "birdmap-sounds"


def _public_object_url(bucket: str, key: str) -> str:
    """Public download URL for an object, correct for both backends this
    project targets. Supabase Storage serves public objects under
    /object/public/ — distinct from the S3-compatible endpoint used for
    uploads — so a bare "{base}/{bucket}/{key}" 404s against real Supabase.
    MinIO (local dev) has no such route and serves a public bucket directly
    at "{base}/{bucket}/{key}", so only insert the segment for Supabase."""
    base = settings.public_s3_url or settings.s3_endpoint
    if "supabase.co" in base:
        return f"{base}/object/public/{bucket}/{key}"
    return f"{base}/{bucket}/{key}"


def ensure_buckets() -> None:
    """Create required buckets if they don't exist. Called once at app startup."""
    try:
        existing = {b["Name"] for b in s3.list_buckets()["Buckets"]}
    except Exception:
        # Supabase Storage doesn't support ListBuckets — skip the check.
        # Buckets are created manually in the Supabase dashboard.
        return
    for bucket in (settings.s3_bucket, settings.model_bucket, SOUNDS_BUCKET):
        if bucket not in existing:
            s3.create_bucket(Bucket=bucket)


def upload_photo(data: bytes, content_type: str = "image/jpeg") -> tuple[str, str]:
    """Upload original + thumbnail, return (photo_url, thumbnail_url)."""
    try:
        img = Image.open(io.BytesIO(data))
        img.verify()  # raises if corrupt
        img = Image.open(io.BytesIO(data))  # reopen after verify (verify closes stream)
    except Exception as e:
        raise ValueError(f"Cannot decode image: {e}") from e

    key = f"sightings/{uuid.uuid4()}.jpg"
    s3.put_object(Bucket=settings.s3_bucket, Key=key, Body=data, ContentType=content_type)

    img.thumbnail((400, 400))
    thumb_buf = io.BytesIO()
    img.save(thumb_buf, format="JPEG", quality=75)
    thumb_key = key.replace("sightings/", "thumbnails/")
    s3.put_object(
        Bucket=settings.s3_bucket,
        Key=thumb_key,
        Body=thumb_buf.getvalue(),
        ContentType="image/jpeg",
    )

    return _public_object_url(settings.s3_bucket, key), _public_object_url(settings.s3_bucket, thumb_key)


def upload_audio(data: bytes, filename: str = "sound.m4a") -> str:
    """Store audio recording, return public URL."""
    ext = filename.rsplit(".", 1)[-1] if "." in filename else "m4a"
    key = f"sounds/{uuid.uuid4()}.{ext}"
    s3.put_object(Bucket=SOUNDS_BUCKET, Key=key, Body=data, ContentType="audio/mp4")
    return _public_object_url(SOUNDS_BUCKET, key)


def upload_model(data: bytes, version: str) -> str:
    """Upload a CoreML model zip, return S3 key."""
    key = f"models/birdmap_{version}.mlpackage.zip"
    s3.put_object(Bucket=settings.model_bucket, Key=key, Body=data, ContentType="application/zip")
    return key


def get_model_download_url(s3_key: str, expires: int = 3600) -> str:
    return s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.model_bucket, "Key": s3_key},
        ExpiresIn=expires,
    )


# ── Media broker (app/api/media.py) ─────────────────────────────────────────
# Separate from upload_photo/upload_audio above, which serve this backend's
# own Postgres-based sightings flow with its own random-key convention.
# These key uploads by the caller-supplied Firestore sighting ID instead,
# matching the path convention the live Firebase-based app already uses
# (sightings/{id}/photo.jpg etc.), so a client that used to write directly to
# Firebase Storage can switch to calling this backend with no other changes.

def _upload_sighting_object(data: bytes, sighting_id: str, filename: str, content_type: str) -> str:
    key = f"sightings/{sighting_id}/{filename}"
    s3.put_object(Bucket=settings.s3_bucket, Key=key, Body=data, ContentType=content_type)
    return _public_object_url(settings.s3_bucket, key)


def upload_sighting_photo(data: bytes, sighting_id: str) -> tuple[str, str]:
    """Upload a sighting's original photo + a 400x400 thumbnail, return (photo_url, thumbnail_url)."""
    try:
        img = Image.open(io.BytesIO(data))
        img.verify()  # raises if corrupt
        img = Image.open(io.BytesIO(data))  # reopen after verify (verify closes stream)
    except Exception as e:
        raise ValueError(f"Cannot decode image: {e}") from e

    photo_url = _upload_sighting_object(data, sighting_id, "photo.jpg", "image/jpeg")

    img.thumbnail((400, 400))
    thumb_buf = io.BytesIO()
    img.save(thumb_buf, format="JPEG", quality=75)
    thumbnail_url = _upload_sighting_object(thumb_buf.getvalue(), sighting_id, "thumbnail.jpg", "image/jpeg")

    return photo_url, thumbnail_url


def upload_sighting_audio(data: bytes, sighting_id: str) -> str:
    """Upload a sighting's audio recording, return its public URL."""
    return _upload_sighting_object(data, sighting_id, "audio.m4a", "audio/mp4")
