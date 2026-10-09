"""CTT-143 (A'): items.version + item_historial eventos completos + sync_conflictos.idempotency_key

Revision ID: c4f1a2b7d9e3
Revises: 7f3a9c2e1b84
Create Date: 2026-10-09

Alcance (backend only, compatible hacia atrás — commits a/b/c de CTT-143):
  - items.version: INT NOT NULL DEFAULT 1 (backfill 1 de filas existentes). La gestiona
    version_id_col del ORM; sube en toda escritura del ítem (A' D2).
  - item_historial: version/diff/dispositivo_id/idempotency_key/actor_rol, todas NULLABLE
    para las filas previas (A' D1/P2). Pasa a ser el registro completo de eventos.
  - sync_conflictos.idempotency_key + UNIQUE PARCIAL (solo no-nulos): lookup previo
    devuelve el mismo conflicto_id en un reintento (A' D4 / CTT-136 absorbido).

NO aplicar en ctt_dev sin OK de Kald (contrato dry-run).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c4f1a2b7d9e3'
down_revision: Union[str, Sequence[str], None] = '7f3a9c2e1b84'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # items.version — autoritativa del servidor. server_default='1' backfillea las filas
    # existentes y cubre inserts no-ORM; el ORM la fija vía version_id_col.
    op.add_column('items', sa.Column('version', sa.Integer(), nullable=False, server_default='1'))

    # item_historial — registro completo de eventos (nullable para filas previas).
    op.add_column('item_historial', sa.Column('version', sa.Integer(), nullable=True))
    op.add_column('item_historial', sa.Column('diff', sa.JSON(), nullable=True))
    op.add_column('item_historial', sa.Column('dispositivo_id', sa.String(length=255), nullable=True))
    op.add_column('item_historial', sa.Column('idempotency_key', sa.String(length=255), nullable=True))
    op.add_column('item_historial', sa.Column('actor_rol', sa.String(length=50), nullable=True))

    # sync_conflictos.idempotency_key + UNIQUE parcial (los NULL no entran al índice).
    op.add_column('sync_conflictos', sa.Column('idempotency_key', sa.String(length=255), nullable=True))
    op.create_index(
        'uq_sync_conflictos_idem', 'sync_conflictos', ['idempotency_key'], unique=True,
        sqlite_where=sa.text('idempotency_key IS NOT NULL'),
        postgresql_where=sa.text('idempotency_key IS NOT NULL'),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index('uq_sync_conflictos_idem', table_name='sync_conflictos')
    op.drop_column('sync_conflictos', 'idempotency_key')
    op.drop_column('item_historial', 'actor_rol')
    op.drop_column('item_historial', 'idempotency_key')
    op.drop_column('item_historial', 'dispositivo_id')
    op.drop_column('item_historial', 'diff')
    op.drop_column('item_historial', 'version')
    op.drop_column('items', 'version')
