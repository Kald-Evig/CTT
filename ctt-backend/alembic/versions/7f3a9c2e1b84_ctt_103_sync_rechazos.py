"""CTT-103: tabla sync_rechazos (dead-letter de rechazos deterministas)

Revision ID: 7f3a9c2e1b84
Revises: 522cc1d85034
Create Date: 2026-10-03 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7f3a9c2e1b84'
down_revision: Union[str, Sequence[str], None] = '522cc1d85034'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'sync_rechazos',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('empresa_id', sa.String(length=36), nullable=False),
        sa.Column('usuario_id', sa.String(length=36), nullable=False),
        sa.Column('instalacion_id', sa.String(length=255), nullable=True),
        sa.Column('idempotency_key', sa.String(length=255), nullable=False),
        # tipo_entidad/entidad_id SIN FK: un 404 de tenant ajeno debe poder guardarse.
        sa.Column('tipo_entidad', sa.String(length=32), nullable=False),
        sa.Column('entidad_id', sa.String(length=255), nullable=False),
        sa.Column('accion', sa.String(length=64), nullable=False),
        sa.Column('payload', sa.JSON(), nullable=False),
        sa.Column('codigo_http', sa.Integer(), nullable=False),
        sa.Column(
            'motivo',
            sa.Enum('transicion_invalida', 'no_autorizado', 'inexistente',
                    name='rechazo_motivo', native_enum=False, create_constraint=True),
            nullable=False,
        ),
        sa.Column('detalle_interno', sa.Text(), nullable=True),
        sa.Column(
            'estado_resolucion',
            sa.Enum('pendiente', 'reaplicado', 'descartado_por_coordinador',
                    name='rechazo_resolucion', native_enum=False, create_constraint=True),
            nullable=False,
        ),
        sa.Column('resuelto_por', sa.String(length=36), nullable=True),
        sa.Column('resuelto_at', sa.DateTime(), nullable=True),
        sa.Column('creado_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'],
                                name=op.f('fk_sync_rechazos_empresa_id_empresas')),
        sa.ForeignKeyConstraint(['usuario_id'], ['usuarios.id'],
                                name=op.f('fk_sync_rechazos_usuario_id_usuarios')),
        sa.ForeignKeyConstraint(['resuelto_por'], ['usuarios.id'],
                                name=op.f('fk_sync_rechazos_resuelto_por_usuarios')),
        sa.PrimaryKeyConstraint('id', name=op.f('pk_sync_rechazos')),
        sa.UniqueConstraint('idempotency_key', 'usuario_id',
                            name='uq_sync_rechazos_key_usuario'),
    )
    # Vista del coordinador (CTT-134): rechazos por resolver de una empresa, recientes primero.
    op.create_index('ix_sync_rechazos_revision', 'sync_rechazos',
                    ['empresa_id', 'estado_resolucion', 'creado_at'])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index('ix_sync_rechazos_revision', table_name='sync_rechazos')
    op.drop_table('sync_rechazos')
