"""create agendas with AI suggestions

Revision ID: 0003_create_agendas
Revises: 0002_create_report_requests
Create Date: 2026-11-03
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0003_create_agendas"
down_revision = "0002_create_report_requests"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "agendas",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_sub", sa.String(length=255), nullable=False),
        sa.Column("agenda", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("ai_suggestion", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("model", sa.String(length=200), nullable=True),
        sa.Column("prompt_version", sa.String(length=100), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_agendas_user_sub", "agendas", ["user_sub"])


def downgrade() -> None:
    op.drop_index("ix_agendas_user_sub", table_name="agendas")
    op.drop_table("agendas")
