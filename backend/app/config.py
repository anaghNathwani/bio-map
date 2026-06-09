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

    class Config:
        env_file = ".env"


settings = Settings()
