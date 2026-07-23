from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str
    secret_key: str
    s3_endpoint: str
    s3_access_key: str
    s3_secret_key: str
    s3_bucket: str = "birdmap-photos"
    model_bucket: str = "birdmap-models"
    access_token_expire_minutes: int = 60 * 24 * 30

    # External URL used in photo/thumbnail URLs returned to clients.
    # In development this matches s3_endpoint; in production point to your
    # CDN or reverse-proxy (e.g. https://storage.yourdomain.com).
    public_s3_url: str = ""

    # Comma-separated list of allowed CORS origins.
    # Use "*" only for local development; set explicit origins in production.
    cors_origins: str = "*"

    # Secret used to authenticate the ML pipeline's POST /model/register call.
    # Generate with: python -c "import secrets; print(secrets.token_hex(32))"
    model_register_secret: str = "change-me"

    # Maximum photo upload size in bytes (default 10 MB)
    max_photo_bytes: int = 10 * 1024 * 1024

    # Optional integrations (leave blank to disable)
    google_cloud_api_key: str = ""
    ebird_api_key: str = ""
    instagram_user_id: str = ""
    instagram_access_token: str = ""

    model_config = {"env_file": ".env", "protected_namespaces": ()}


settings = Settings()
