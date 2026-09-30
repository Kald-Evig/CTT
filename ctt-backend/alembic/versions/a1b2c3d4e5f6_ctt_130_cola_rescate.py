"""CTT-130 fase 4b: tabla cola_rescate (cuarentena del rescate)

Revision ID: a1b2c3d4e5f6
Revises: 9aab29aa04ad
Create Date: 2026-09-29 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = '9aab29aa04ad'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'cola_rescate',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('instalacion_id', sa.String(length=255), nullable=False),
        sa.Column('subido_por', sa.String(length=36), nullable=False),
        sa.Column('usuario_id', sa.String(length=36), nullable=False),
        sa.Column('empresa_id', sa.String(length=36), nullable=False),
        sa.Column('idempotency_key', sa.String(length=255), nullable=False),
        sa.Column('secuencia', sa.Integer(), nullable=True),
        sa.Column('tipo_entidad', sa.String(length=64), nullable=False),
        sa.Column('entidad_id', sa.String(length=255), nullable=False),
        sa.Column('accion', sa.String(length=64), nullable=False),
        sa.Column('fila', sa.JSON(), nullable=False),
        sa.Column('subido_por_tercero', sa.Boolean(), nullable=False),
        sa.Column(
            'estado_revision',
            sa.Enum('pendiente_revision', 'ya_aplicada', name='rescate_estado',
                    native_enum=False, create_constraint=True),
            nullable=False,
        ),
        sa.Column('recibido_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'],
                                name=op.f('fk_cola_rescate_empresa_id_empresas')),
        sa.ForeignKeyConstraint(['subido_por'], ['usuarios.id'],
                                name=op.f('fk_cola_rescate_subido_por_usuarios')),
        sa.PrimaryKeyConstraint('id', name=op.f('pk_cola_rescate')),
        sa.UniqueConstraint('idempotency_key', name='uq_cola_rescate_idempotency'),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('cola_rescate')
