import io
import uuid
import boto3
from PIL import Image
from app.config import settings

s3 = boto3.client(
    "s3",
    endpoint_url=settings.s3_endpoint,
    aws_access_key_id=settings.s3_access_key,
    aws_secret_access_key=settings.s3_secret_key,
    # Supabase Storage and MinIO both work without a real AWS region
    region_name="us-east-1",
)


def ensure_buckets() -> None:
    """Create required buckets if they don't exist. Called once at app startup."""
    try:
        existing = {b["Name"] for b in s3.list_buckets()["Buckets"]}
    except Exception:
        # Supabase Storage doesn't support ListBuckets — skip the check.
        # Buckets are created manually in the Supabase dashboard.
        return
    for bucket in (settings.s3_bucket, settings.model_bucket):
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

    public_base = (settings.public_s3_url or settings.s3_endpoint)
    base = f"{public_base}/{settings.s3_bucket}"
    return f"{base}/{key}", f"{base}/{thumb_key}"


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
