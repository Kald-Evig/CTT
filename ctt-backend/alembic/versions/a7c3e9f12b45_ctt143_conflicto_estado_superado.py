"""CTT-143 (21-oct): ConflictoEstado.SUPERADO

Revision ID: a7c3e9f12b45
Revises: c4f1a2b7d9e3
Create Date: 2026-10-21

Agrega el valor 'superado' al CHECK del enum `sync_conflictos.estado` (B3). El enum es
`SAEnum(native_enum=False, create_constraint=True, name="estado")`, así que en Postgres se
materializa como un CHECK nombrado por la naming convention `ck_sync_conflictos_estado`
(ck_%(table_name)s_%(constraint_name)s). Se recrea el CHECK con el nuevo valor.

Orientada a Postgres (ctt_dev). Los tests NO usan alembic: recrean el esquema desde los
modelos (create_all), por lo que 'superado' ya es válido ahí sin esta migración.

NO aplicar en ctt_dev sin OK de Kald (contrato dry-run). Se entrega junto con su --sql.
"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'a7c3e9f12b45'
down_revision: Union[str, Sequence[str], None] = 'c4f1a2b7d9e3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# constraint_name del SAEnum (name="estado"). La naming convention de la metadata
# (ck_%(table_name)s_%(constraint_name)s) le antepone el prefijo → ck_sync_conflictos_estado,
# que es el nombre real del CHECK existente. NO prefijar a mano (quedaría doble).
_CK = 'estado'
_TABLA = 'sync_conflictos'


def upgrade() -> None:
    op.drop_constraint(_CK, _TABLA, type_='check')
    op.create_check_constraint(
        _CK, _TABLA, "estado IN ('pendiente', 'resuelto', 'superado')"
    )


def downgrade() -> None:
    # Caveat: si existen filas en 'superado', este downgrade falla al revalidar el CHECK.
    # Resolverlas o reasignarlas antes de bajar la migración.
    op.drop_constraint(_CK, _TABLA, type_='check')
    op.create_check_constraint(
        _CK, _TABLA, "estado IN ('pendiente', 'resuelto')"
    )
