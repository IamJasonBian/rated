"""Add flexible Airtable-compatible records table

Revision ID: c5e7a91d4b22
Revises: a3c4d2e9b1f7
Create Date: 2026-06-16 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "c5e7a91d4b22"
down_revision: Union[str, None] = "a3c4d2e9b1f7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "records",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("table_name", sa.String(), nullable=False),
        sa.Column("fields", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.Float(), nullable=False),
        sa.Column("updated_at", sa.Float(), nullable=True),
    )
    op.create_index("ix_records_table_created", "records", ["table_name", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_records_table_created", table_name="records")
    op.drop_table("records")
