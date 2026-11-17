"""CTT-161: ventana de terminados - items.terminado_en + empresas.dias_ventana_terminados

Revision ID: c7e9a1b3d5f2
Revises: b5d4e6f8a1c2
Create Date: 2026-11-17

CTT-161 (subtarea backend de CTT-152):
  - items.terminado_en (nullable): instante en que el ítem pasó a TERMINADO (naive=UTC,
    convención vigente del esquema). Lo mantiene registrar_escritura_item.
  - empresas.dias_ventana_terminados (NOT NULL, default 30, CHECK > 0): N de días que
    /items/mis-items sigue enviando un terminado. Sin endpoint de edición en este ticket.
  - índice parcial (asignado_a, terminado_en) WHERE estado = 'terminado'.
  - backfill de terminado_en para los terminados existentes: MAX(item_historial.created_at)
    de los eventos hacia 'terminado'; si el ítem no tiene historial (seed.py / fixtures),
    updated_at como respaldo. Tras el backfill ningún terminado queda con terminado_en NULL.

Orientada a Postgres (ctt_dev). Los tests recrean el esquema desde los modelos (create_all),
no via alembic. NO aplicar en ctt_dev sin OK de Kald (dry-run --sql en .evidencia/).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'c7e9a1b3d5f2'
down_revision: Union[str, Sequence[str], None] = 'b5d4e6f8a1c2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# Backfill: el último evento del historial hacia 'terminado' da la fecha de término
# (tras una reversión + re-término manda el más reciente, por eso MAX). Si no hay
# historial, updated_at. Solo toca los ítems actualmente en estado 'terminado'.
_BACKFILL_TERMINADO_EN = """
    UPDATE items
       SET terminado_en = COALESCE(
               (SELECT MAX(h.created_at)
                  FROM item_historial h
                 WHERE h.item_id = items.id
                   AND h.estado_nuevo = 'terminado'),
               items.updated_at)
     WHERE items.estado = 'terminado'
"""


def upgrade() -> None:
    op.add_column('items', sa.Column('terminado_en', sa.DateTime(), nullable=True))
    op.add_column(
        'empresas',
        sa.Column('dias_ventana_terminados', sa.Integer(), nullable=False,
                  server_default=sa.text('30')),
    )
    # El nombre va SIN el prefijo ck_<tabla>_: la naming_convention de la metadata
    # (database.py: "ck_%(table_name)s_%(constraint_name)s") lo antepone → el nombre
    # final es ck_empresas_dias_ventana_terminados_pos. Pasar el nombre completo lo
    # duplicaría (ck_empresas_ck_empresas_...).
    op.create_check_constraint(
        'dias_ventana_terminados_pos', 'empresas',
        'dias_ventana_terminados > 0',
    )
    op.execute(_BACKFILL_TERMINADO_EN)
    op.create_index(
        'ix_items_asignado_terminado_en', 'items', ['asignado_a', 'terminado_en'],
        postgresql_where=sa.text("estado = 'terminado'"),
        sqlite_where=sa.text("estado = 'terminado'"),
    )


def downgrade() -> None:
    op.drop_index('ix_items_asignado_terminado_en', table_name='items')
    op.drop_constraint('dias_ventana_terminados_pos', 'empresas', type_='check')
    op.drop_column('empresas', 'dias_ventana_terminados')
    op.drop_column('items', 'terminado_en')
