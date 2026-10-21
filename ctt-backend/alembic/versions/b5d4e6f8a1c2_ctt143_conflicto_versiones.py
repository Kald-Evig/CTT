"""CTT-143 (B4): sync_conflictos.version_capturada/version_resultante/estado_resultante

Revision ID: b5d4e6f8a1c2
Revises: a7c3e9f12b45
Create Date: 2026-10-21

B4:
  - version_capturada: versión del ítem al CREAR el conflicto (precondición de la
    resolución 'local' → 409 'obsoleto' si el ítem avanzó).
  - version_resultante / estado_resultante: versión y estado del ítem tras resolver, para
    que el reconciliador del cliente escriba base+version sin re-pull (P6).
Todas NULLABLE: los conflictos previos no las traen.

Orientada a Postgres (ctt_dev). Los tests recrean el esquema desde los modelos (create_all),
no via alembic. NO aplicar en ctt_dev sin OK de Kald (dry-run --sql en .evidencia/).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'b5d4e6f8a1c2'
down_revision: Union[str, Sequence[str], None] = 'a7c3e9f12b45'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('sync_conflictos', sa.Column('version_capturada', sa.Integer(), nullable=True))
    op.add_column('sync_conflictos', sa.Column('version_resultante', sa.Integer(), nullable=True))
    op.add_column('sync_conflictos', sa.Column('estado_resultante', sa.String(length=50), nullable=True))


def downgrade() -> None:
    op.drop_column('sync_conflictos', 'estado_resultante')
    op.drop_column('sync_conflictos', 'version_resultante')
    op.drop_column('sync_conflictos', 'version_capturada')
