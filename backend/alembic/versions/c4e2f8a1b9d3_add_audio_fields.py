"""add audio fields and media_type to sightings

Revision ID: c4e2f8a1b9d3
Revises: b3f1a2c4d5e6
Create Date: 2026-07-21 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "c4e2f8a1b9d3"
down_revision: Union[str, None] = "b3f1a2c4d5e6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("sightings", sa.Column("media_type", sa.String(10), nullable=False, server_default="photo"))
    op.add_column("sightings", sa.Column("audio_url", sa.String(1024), nullable=True))
    op.alter_column("sightings", "photo_url", nullable=True)


def downgrade() -> None:
    op.alter_column("sightings", "photo_url", nullable=False)
    op.drop_column("sightings", "audio_url")
    op.drop_column("sightings", "media_type")
