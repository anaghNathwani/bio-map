"""initial schema

Revision ID: 7023abd281b4
Revises:
Create Date: 2026-06-15 16:41:31.457065

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geometry


# revision identifiers, used by Alembic.
revision: str = '7023abd281b4'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("username", sa.String(80), nullable=False),
        sa.Column("hashed_password", sa.String(255), nullable=False),
        sa.Column("annotation_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)
    op.create_index("ix_users_username", "users", ["username"], unique=True)

    op.create_table(
        "sightings",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("photo_url", sa.String(1024), nullable=False),
        sa.Column("thumbnail_url", sa.String(1024), nullable=True),
        sa.Column("location", Geometry("POINT", srid=4326), nullable=False),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("ai_species_suggestion", sa.String(255), nullable=True),
        sa.Column("ai_confidence", sa.Float(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_sightings_user_id", "sightings", ["user_id"])

    op.create_table(
        "annotations",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("sighting_id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("species", sa.String(255), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False, server_default="1.0"),
        sa.Column("behavior", sa.String(255), nullable=True),
        sa.Column("age_plumage", sa.String(100), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["sighting_id"], ["sightings.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_annotations_sighting_id", "annotations", ["sighting_id"])
    op.create_index("ix_annotations_user_id", "annotations", ["user_id"])

    op.create_table(
        "model_versions",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("version", sa.String(50), nullable=False),
        sa.Column("s3_key", sa.String(1024), nullable=False),
        sa.Column("num_classes", sa.Integer(), nullable=False),
        sa.Column("accuracy", sa.Float(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("version"),
    )


def downgrade() -> None:
    op.drop_table("model_versions")
    op.drop_index("ix_annotations_user_id", table_name="annotations")
    op.drop_index("ix_annotations_sighting_id", table_name="annotations")
    op.drop_table("annotations")
    op.drop_index("ix_sightings_user_id", table_name="sightings")
    op.drop_table("sightings")
    op.drop_index("ix_users_username", table_name="users")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
