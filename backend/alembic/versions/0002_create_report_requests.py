"""create report request outbox

Revision ID: 0002_create_report_requests
Revises: 0001_create_meetings
Create Date: 2026-11-01
"""

import sqlalchemy as sa

from alembic import op

revision = "0002_create_report_requests"
down_revision = "0001_create_meetings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "report_requests",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("week", sa.String(length=8), nullable=False),
        sa.Column("requester_sub", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_report_requests_pending",
        "report_requests",
        ["processed_at", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_report_requests_pending", table_name="report_requests")
    op.drop_table("report_requests")
