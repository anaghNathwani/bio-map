import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, Text, Float
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geometry
from app.database import Base


class Sighting(Base):
    __tablename__ = "sightings"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True)
    photo_url: Mapped[str] = mapped_column(String(1024))
    thumbnail_url: Mapped[str] = mapped_column(String(1024), nullable=True)
    location: Mapped[object] = mapped_column(Geometry("POINT", srid=4326))
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    notes: Mapped[str] = mapped_column(Text, nullable=True)
    # AI suggestion at upload time (may be empty for v1 cold-start)
    ai_species_suggestion: Mapped[str] = mapped_column(String(255), nullable=True)
    ai_confidence: Mapped[float] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    user: Mapped["User"] = relationship(back_populates="sightings")  # noqa: F821
    annotations: Mapped[list["Annotation"]] = relationship(back_populates="sighting")  # noqa: F821
