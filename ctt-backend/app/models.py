"""
models.py — Modelos ORM (SQLAlchemy 2.0) que reflejan el modelo de datos del DDT
(Sección 5).

Convenciones:
  - PKs y FKs son UUID, almacenados como String(36) para portabilidad SQLite↔Postgres.
    En Postgres puede migrarse a tipo UUID nativo sin cambiar la lógica.
  - `empresa_id` aparece en toda tabla con datos de negocio para aislar tenants
    (Sección 4.2). El filtrado por empresa_id se aplica en la capa de servicio/router.
  - Se añaden tres tablas no listadas explícitamente en la Sección 5 pero EXIGIDAS
    por funcionalidades del MVP, marcadas con [EXTENSIÓN]:
        item_comentarios  -> "Agregar comentario" (matriz de permisos)
        item_historial    -> "Ver log de cambios" / Reportes Sección 10
        notificaciones    -> Sección 9
    Y un campo [EXTENSIÓN] en items: `estado_previo`, necesario para implementar
    "PROBLEMA -> estado anterior" (Sección 6.2).
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean, Date, DateTime, Enum as SAEnum, Float, ForeignKey, Integer,
    String, Text, JSON,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.enums import (
    ConflictoEstado, EmpresaEstado, EmpresaPlan, EvidenciaSyncStatus,
    ItemEstado, ProblemaEstado, ProyectoEstado, Rol, UsuarioEstado,
)


def _uuid() -> str:
    """Genera un UUID v4 como string (PK por defecto)."""
    return str(uuid.uuid4())


def _now() -> datetime:
    """Timestamp en UTC (consistente para sincronización offline, Sección 8)."""
    return datetime.now(timezone.utc)


# ─────────────────────────────────────────────────────────────────────────────
# EMPRESAS (tenants)
# ─────────────────────────────────────────────────────────────────────────────
class Empresa(Base):
    __tablename__ = "empresas"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    nombre: Mapped[str] = mapped_column(String(255))
    rut_empresa: Mapped[str] = mapped_column(String(20), unique=True)  # RUT chileno
    email_contacto: Mapped[str] = mapped_column(String(255))
    plan: Mapped[EmpresaPlan] = mapped_column(SAEnum(EmpresaPlan), default=EmpresaPlan.TRIAL)
    estado: Mapped[EmpresaEstado] = mapped_column(SAEnum(EmpresaEstado), default=EmpresaEstado.TRIAL)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    # Relaciones
    miembros: Mapped[list["EmpresaUsuario"]] = relationship(back_populates="empresa")
    proyectos: Mapped[list["Proyecto"]] = relationship(back_populates="empresa")


# ─────────────────────────────────────────────────────────────────────────────
# USUARIOS
# ─────────────────────────────────────────────────────────────────────────────
class Usuario(Base):
    __tablename__ = "usuarios"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    # UID de Firebase Auth. En modo mock se puede dejar igual al id interno.
    firebase_uid: Mapped[str] = mapped_column(String(128), unique=True)
    nombre_completo: Mapped[str] = mapped_column(String(255))
    # RUT chileno: único, NULLABLE — conecta con contratos/RRHH (Sección 14.2).
    rut: Mapped[str | None] = mapped_column(String(20), unique=True, nullable=True)
    email: Mapped[str] = mapped_column(String(255), unique=True)
    telefono: Mapped[str | None] = mapped_column(String(20), nullable=True)
    estado: Mapped[UsuarioEstado] = mapped_column(SAEnum(UsuarioEstado), default=UsuarioEstado.ACTIVO)
    # Flag de plataforma: Super Admin (Sección 2.1). No es un rol de empresa.
    es_super_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    empresas: Mapped[list["EmpresaUsuario"]] = relationship(back_populates="usuario")


# ─────────────────────────────────────────────────────────────────────────────
# EMPRESA_USUARIO (junction: un usuario puede pertenecer a N empresas con rol distinto)
# ─────────────────────────────────────────────────────────────────────────────
class EmpresaUsuario(Base):
    __tablename__ = "empresa_usuario"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    empresa_id: Mapped[str] = mapped_column(ForeignKey("empresas.id"))
    usuario_id: Mapped[str] = mapped_column(ForeignKey("usuarios.id"))
    rol: Mapped[Rol] = mapped_column(SAEnum(Rol))
    estado: Mapped[UsuarioEstado] = mapped_column(SAEnum(UsuarioEstado), default=UsuarioEstado.ACTIVO)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    empresa: Mapped["Empresa"] = relationship(back_populates="miembros")
    usuario: Mapped["Usuario"] = relationship(back_populates="empresas")


# ─────────────────────────────────────────────────────────────────────────────
# PROYECTOS
# ─────────────────────────────────────────────────────────────────────────────
class Proyecto(Base):
    __tablename__ = "proyectos"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    empresa_id: Mapped[str] = mapped_column(ForeignKey("empresas.id"))  # aislamiento tenant
    nombre: Mapped[str] = mapped_column(String(255))
    descripcion: Mapped[str | None] = mapped_column(Text, nullable=True)
    ubicacion_nombre: Mapped[str | None] = mapped_column(String(500), nullable=True)
    # Referencia geográfica textual/coordenadas — NO es GPS tracking (eso es Fase 2).
    latitud: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitud: Mapped[float | None] = mapped_column(Float, nullable=True)
    coordinador_principal_id: Mapped[str | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    estado: Mapped[ProyectoEstado] = mapped_column(SAEnum(ProyectoEstado), default=ProyectoEstado.ACTIVO)
    fecha_inicio: Mapped[datetime | None] = mapped_column(Date, nullable=True)
    fecha_fin_estimada: Mapped[datetime | None] = mapped_column(Date, nullable=True)
    created_by: Mapped[str | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now)

    empresa: Mapped["Empresa"] = relationship(back_populates="proyectos")
    items: Mapped[list["Item"]] = relationship(back_populates="proyecto")
    asignaciones: Mapped[list["ProyectoUsuario"]] = relationship(back_populates="proyecto")


# ─────────────────────────────────────────────────────────────────────────────
# PROYECTO_USUARIO (junction: residentes y trabajadores asignados a un proyecto)
# ─────────────────────────────────────────────────────────────────────────────
class ProyectoUsuario(Base):
    __tablename__ = "proyecto_usuarios"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    proyecto_id: Mapped[str] = mapped_column(ForeignKey("proyectos.id"))
    usuario_id: Mapped[str] = mapped_column(ForeignKey("usuarios.id"))
    rol_en_proyecto: Mapped[Rol] = mapped_column(SAEnum(Rol))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    proyecto: Mapped["Proyecto"] = relationship(back_populates="asignaciones")


# ─────────────────────────────────────────────────────────────────────────────
# ITEMS (árbol recursivo: parent_item_id apunta a otro item)
# ─────────────────────────────────────────────────────────────────────────────
class Item(Base):
    __tablename__ = "items"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    proyecto_id: Mapped[str] = mapped_column(ForeignKey("proyectos.id"))
    # NULL = ítem raíz del proyecto. Self-FK para el árbol jerárquico.
    parent_item_id: Mapped[str | None] = mapped_column(ForeignKey("items.id"), nullable=True)
    nivel_profundidad: Mapped[int] = mapped_column(Integer, default=0)  # 0 = raíz
    nombre: Mapped[str] = mapped_column(String(255))
    descripcion: Mapped[str | None] = mapped_column(Text, nullable=True)
    asignado_a: Mapped[str | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    estado: Mapped[ItemEstado] = mapped_column(SAEnum(ItemEstado), default=ItemEstado.ABIERTO)
    # [EXTENSIÓN] estado al que se debe volver al cerrar un PROBLEMA (Sección 6.2).
    estado_previo: Mapped[ItemEstado | None] = mapped_column(SAEnum(ItemEstado), nullable=True)
    fecha_inicio_estimada: Mapped[datetime | None] = mapped_column(Date, nullable=True)
    duracion_estimada_horas: Mapped[float | None] = mapped_column(Float, nullable=True)
    fecha_limite: Mapped[datetime | None] = mapped_column(Date, nullable=True)  # para reporte de retraso
    orden: Mapped[int] = mapped_column(Integer, default=0)
    created_by: Mapped[str | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now)

    # Relaciones
    proyecto: Mapped["Proyecto"] = relationship(back_populates="items")
    hijos: Mapped[list["Item"]] = relationship(
        back_populates="padre", remote_side=lambda: [Item.parent_item_id]
    )
    padre: Mapped["Item | None"] = relationship(
        back_populates="hijos", remote_side=lambda: [Item.id]
    )
    problemas: Mapped[list["ItemProblema"]] = relationship(back_populates="item")
    comentarios: Mapped[list["ItemComentario"]] = relationship(back_populates="item")
    evidencias: Mapped[list["ItemEvidencia"]] = relationship(back_populates="item")
    historial: Mapped[list["ItemHistorial"]] = relationship(back_populates="item")


# ─────────────────────────────────────────────────────────────────────────────
# ITEM_PROBLEMAS
# ─────────────────────────────────────────────────────────────────────────────
class ItemProblema(Base):
    __tablename__ = "item_problemas"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    item_id: Mapped[str] = mapped_column(ForeignKey("items.id"))
    reportado_por: Mapped[str] = mapped_column(ForeignKey("usuarios.id"))
    descripcion: Mapped[str] = mapped_column(Text)  # obligatoria
    estado: Mapped[ProblemaEstado] = mapped_column(SAEnum(ProblemaEstado), default=ProblemaEstado.ABIERTO)
    cerrado_por: Mapped[str | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    cerrado_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    item: Mapped["Item"] = relationship(back_populates="problemas")


# ─────────────────────────────────────────────────────────────────────────────
# ITEM_EVIDENCIAS (fotos — Sección 4.4 y 8.3)
# ─────────────────────────────────────────────────────────────────────────────
class ItemEvidencia(Base):
    __tablename__ = "item_evidencias"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    item_id: Mapped[str] = mapped_column(ForeignKey("items.id"))
    usuario_id: Mapped[str] = mapped_column(ForeignKey("usuarios.id"))
    s3_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    s3_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    thumbnail_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    sync_status: Mapped[EvidenciaSyncStatus] = mapped_column(
        SAEnum(EvidenciaSyncStatus), default=EvidenciaSyncStatus.PENDIENTE
    )
    device_timestamp: Mapped[datetime] = mapped_column(DateTime, default=_now)  # tomada offline
    server_timestamp: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    item: Mapped["Item"] = relationship(back_populates="evidencias")


# ─────────────────────────────────────────────────────────────────────────────
# ITEM_COMENTARIOS  [EXTENSIÓN — soporta "Agregar comentario" de la matriz 2.2]
# ─────────────────────────────────────────────────────────────────────────────
class ItemComentario(Base):
    __tablename__ = "item_comentarios"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    item_id: Mapped[str] = mapped_column(ForeignKey("items.id"))
    usuario_id: Mapped[str] = mapped_column(ForeignKey("usuarios.id"))
    texto: Mapped[str] = mapped_column(Text)
    # Los comentarios NUNCA generan conflicto de sync (Sección 8.4): solo se agregan.
    device_timestamp: Mapped[datetime] = mapped_column(DateTime, default=_now)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    item: Mapped["Item"] = relationship(back_populates="comentarios")


# ─────────────────────────────────────────────────────────────────────────────
# ITEM_HISTORIAL  [EXTENSIÓN — "log de cambios" / Reportes Sección 10]
# ─────────────────────────────────────────────────────────────────────────────
class ItemHistorial(Base):
    __tablename__ = "item_historial"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    item_id: Mapped[str] = mapped_column(ForeignKey("items.id"))
    usuario_id: Mapped[str | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    accion: Mapped[str] = mapped_column(String(100))           # p.ej. "cambio_estado"
    estado_anterior: Mapped[str | None] = mapped_column(String(50), nullable=True)
    estado_nuevo: Mapped[str | None] = mapped_column(String(50), nullable=True)
    detalle: Mapped[str | None] = mapped_column(Text, nullable=True)  # comentario/descr.
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    item: Mapped["Item"] = relationship(back_populates="historial")


# ─────────────────────────────────────────────────────────────────────────────
# SYNC_CONFLICTOS (Sección 8)
# ─────────────────────────────────────────────────────────────────────────────
class SyncConflicto(Base):
    __tablename__ = "sync_conflictos"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    item_id: Mapped[str] = mapped_column(ForeignKey("items.id"))
    cambio_local: Mapped[dict] = mapped_column(JSON)     # snapshot del cambio offline
    cambio_servidor: Mapped[dict] = mapped_column(JSON)  # estado del servidor al conflicto
    dispositivo_id: Mapped[str] = mapped_column(String(255))
    usuario_id: Mapped[str] = mapped_column(ForeignKey("usuarios.id"))
    estado: Mapped[ConflictoEstado] = mapped_column(SAEnum(ConflictoEstado), default=ConflictoEstado.PENDIENTE)
    resuelto_por: Mapped[str | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    resuelto_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


# ─────────────────────────────────────────────────────────────────────────────
# NOTIFICACIONES  [EXTENSIÓN — Sección 9]
# ─────────────────────────────────────────────────────────────────────────────
class Notificacion(Base):
    __tablename__ = "notificaciones"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    empresa_id: Mapped[str] = mapped_column(ForeignKey("empresas.id"))
    usuario_id: Mapped[str] = mapped_column(ForeignKey("usuarios.id"))  # destinatario
    evento: Mapped[str] = mapped_column(String(100))   # p.ej. "item_asignado"
    titulo: Mapped[str] = mapped_column(String(255))
    cuerpo: Mapped[str | None] = mapped_column(Text, nullable=True)
    leida: Mapped[bool] = mapped_column(Boolean, default=False)
    email_enviado: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
