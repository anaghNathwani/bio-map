import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, Float, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Annotation(Base):
    __tablename__ = "annotations"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    sighting_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("sightings.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True)
    species: Mapped[str] = mapped_column(String(255))
    confidence: Mapped[float] = mapped_column(Float, default=1.0)  # annotator self-rating 0-1
    behavior: Mapped[str] = mapped_column(String(255), nullable=True)
    age_plumage: Mapped[str] = mapped_column(String(100), nullable=True)  # e.g. "adult", "juvenile"
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    sighting: Mapped["Sighting"] = relationship(back_populates="annotations")  # noqa: F821
    user: Mapped["User"] = relationship(back_populates="annotations")  # noqa: F821


class ModelVersion(Base):
    __tablename__ = "model_versions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    version: Mapped[str] = mapped_column(String(50), unique=True)
    s3_key: Mapped[str] = mapped_column(String(1024))
    num_classes: Mapped[int] = mapped_column(Integer)
    accuracy: Mapped[float] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    is_active: Mapped[bool] = mapped_column(default=True)
