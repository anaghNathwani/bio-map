"""add cascade deletes on foreign keys

Revision ID: b3f1a2c4d5e6
Revises: 7023abd281b4
Create Date: 2026-07-14 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op

revision: str = 'b3f1a2c4d5e6'
down_revision: Union[str, None] = '7023abd281b4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # sightings.user_id → CASCADE
    op.drop_constraint("sightings_user_id_fkey", "sightings", type_="foreignkey")
    op.create_foreign_key(
        "sightings_user_id_fkey", "sightings", "users", ["user_id"], ["id"], ondelete="CASCADE"
    )

    # annotations.sighting_id → CASCADE
    op.drop_constraint("annotations_sighting_id_fkey", "annotations", type_="foreignkey")
    op.create_foreign_key(
        "annotations_sighting_id_fkey", "annotations", "sightings", ["sighting_id"], ["id"], ondelete="CASCADE"
    )

    # annotations.user_id → CASCADE
    op.drop_constraint("annotations_user_id_fkey", "annotations", type_="foreignkey")
    op.create_foreign_key(
        "annotations_user_id_fkey", "annotations", "users", ["user_id"], ["id"], ondelete="CASCADE"
    )


def downgrade() -> None:
    op.drop_constraint("annotations_user_id_fkey", "annotations", type_="foreignkey")
    op.create_foreign_key(
        "annotations_user_id_fkey", "annotations", "users", ["user_id"], ["id"]
    )

    op.drop_constraint("annotations_sighting_id_fkey", "annotations", type_="foreignkey")
    op.create_foreign_key(
        "annotations_sighting_id_fkey", "annotations", "sightings", ["sighting_id"], ["id"]
    )

    op.drop_constraint("sightings_user_id_fkey", "sightings", type_="foreignkey")
    op.create_foreign_key(
        "sightings_user_id_fkey", "sightings", "users", ["user_id"], ["id"]
    )
