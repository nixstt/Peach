"""create meetings

Revision ID: 0001_create_meetings
Revises:
Create Date: 2026-10-28
"""

import sqlalchemy as sa

from alembic import op

revision = "0001_create_meetings"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "meetings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attendee_count", sa.Integer(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("meetings")
