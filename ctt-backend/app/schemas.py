"""
schemas.py — Esquemas Pydantic (v2) de entrada y salida.

Separan el contrato de la API del modelo ORM. Los modelos *Out usan
`from_attributes=True` para construirse directamente desde objetos SQLAlchemy.
"""

import re
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.enums import (
    EmpresaPlan, EvidenciaSyncStatus, ItemEstado, ProyectoEstado, Rol, UsuarioEstado,
)

_PATRON_RUT = re.compile(r"^\d{1,3}(?:\.\d{3})*-[\dkK]$")


def _validar_rut_chileno(rut: str) -> str:
    """Acepta formatos '12.345.678-9' y '12345678-9'; normaliza dígito verificador a mayúscula."""
    if not _PATRON_RUT.match(rut):
        raise ValueError("RUT inválido. Use el formato 12.345.678-9 o 12345678-9.")
    return rut.upper()


# ── Empresas ─────────────────────────────────────────────────────────────────
class EmpresaCreate(BaseModel):
    nombre: str = Field(min_length=1, max_length=255)
    rut_empresa: str = Field(min_length=1, max_length=20)
    email_contacto: EmailStr
    plan: EmpresaPlan = Field(default=EmpresaPlan.TRIAL)

    @field_validator("rut_empresa")
    @classmethod
    def validar_rut_empresa(cls, v: str) -> str:
        return _validar_rut_chileno(v)


class EmpresaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    nombre: str
    rut_empresa: str
    email_contacto: str
    plan: EmpresaPlan
    estado: str


# ── Usuarios ─────────────────────────────────────────────────────────────────
class UsuarioCreate(BaseModel):
    nombre_completo: str = Field(min_length=1, max_length=255)
    rut: str | None = Field(default=None, max_length=20)
    email: EmailStr
    telefono: str | None = Field(default=None, max_length=20)
    rol: Rol  # rol con el que se crea en la empresa activa

    @field_validator("rut")
    @classmethod
    def validar_rut_usuario(cls, v: str | None) -> str | None:
        return _validar_rut_chileno(v) if v is not None else v


class UsuarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    nombre_completo: str
    rut: str | None
    email: str
    estado: str
    rol: str


class UsuarioCreateOut(UsuarioOut):
    """Respuesta de POST /usuarios: incluye el reset link para que el Admin lo entregue al usuario."""
    reset_link: str | None = None
    reset_link_pendiente: bool = False


class UsuarioEstadoUpdate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    estado: UsuarioEstado


class UsuarioRolUpdate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    rol: Rol


# ── Proyectos ────────────────────────────────────────────────────────────────
class ProyectoCreate(BaseModel):
    nombre: str = Field(min_length=1, max_length=255)
    descripcion: str | None = Field(default=None, max_length=2000)
    ubicacion_nombre: str | None = Field(default=None, max_length=500)
    latitud: float | None = Field(default=None, ge=-90.0, le=90.0)
    longitud: float | None = Field(default=None, ge=-180.0, le=180.0)
    coordinador_principal_id: str | None = None
    fecha_inicio: date | None = None
    fecha_fin_estimada: date | None = None


class ProyectoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    empresa_id: str
    nombre: str
    descripcion: str | None
    ubicacion_nombre: str | None
    latitud: float | None
    longitud: float | None
    coordinador_principal_id: str | None
    estado: ProyectoEstado
    fecha_inicio: date | None
    fecha_fin_estimada: date | None


class ProyectoUpdate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    nombre: str | None = Field(default=None, min_length=1, max_length=255)
    descripcion: str | None = Field(default=None, max_length=2000)
    ubicacion_nombre: str | None = Field(default=None, max_length=500)
    latitud: float | None = Field(default=None, ge=-90.0, le=90.0)
    longitud: float | None = Field(default=None, ge=-180.0, le=180.0)
    coordinador_principal_id: str | None = None
    fecha_inicio: date | None = None
    fecha_fin_estimada: date | None = None

    @field_validator('nombre', mode='before')
    @classmethod
    def nombre_no_puede_ser_null(cls, v: object) -> object:
        if v is None:
            raise ValueError("nombre es NOT NULL; omití el campo para no modificarlo.")
        return v


class AsignarUsuarioProyectoIn(BaseModel):
    model_config = ConfigDict(extra='forbid')
    usuario_id: str = Field(min_length=1)


class ProyectoUsuarioOut(BaseModel):
    usuario_id: str
    nombre_completo: str
    rol_en_proyecto: Rol
    estado: UsuarioEstado


# ── Ítems ────────────────────────────────────────────────────────────────────
class ItemCreate(BaseModel):
    proyecto_id: str
    parent_item_id: str | None = None
    nombre: str = Field(min_length=1, max_length=255)
    descripcion: str | None = Field(default=None, max_length=2000)
    asignado_a: str | None = None
    fecha_limite: date | None = None
    duracion_estimada_horas: float | None = None
    orden: int = 0


class ItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    proyecto_id: str
    parent_item_id: str | None
    nivel_profundidad: int
    nombre: str
    descripcion: str | None
    asignado_a: str | None
    asignado_nombre: str | None = None
    estado: ItemEstado
    fecha_limite: date | None
    duracion_estimada_horas: float | None = None
    orden: int = 0
    ultima_edicion_por: str | None = None
    ultima_edicion_en: datetime | None = None


class ItemUpdate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    nombre: str | None = Field(default=None, min_length=1, max_length=255)
    descripcion: str | None = Field(default=None, max_length=2000)
    fecha_limite: date | None = None
    orden: int | None = None
    duracion_estimada_horas: float | None = None

    @field_validator('nombre', 'orden', mode='before')
    @classmethod
    def campos_not_null_no_aceptan_null(cls, v: object, info) -> object:
        if v is None:
            raise ValueError(
                f"{info.field_name} es NOT NULL; omití el campo para no modificarlo."
            )
        return v


class AsignarItemIn(BaseModel):
    usuario_id: str = Field(min_length=1)


class TransicionIn(BaseModel):
    """Cambio de estado de un ítem (Sección 6 y 8).

    device_timestamp y dispositivo_id son opcionales: los envía el SyncService
    cuando aplica cambios encolados offline. Su presencia habilita la detección
    de conflictos de concurrencia en el backend (Sección 8).
    """
    nuevo_estado: ItemEstado
    comentario: str | None = Field(default=None, max_length=1000)
    descripcion_problema: str | None = Field(default=None, max_length=2000)
    device_timestamp: datetime | None = None
    dispositivo_id: str | None = Field(default=None, max_length=255)


class ComentarioIn(BaseModel):
    texto: str = Field(min_length=1, max_length=2000)


class ComentarioOut(BaseModel):
    id: str
    usuario_id: str
    nombre_usuario: str | None
    texto: str
    created_at: datetime


class EvidenciaIn(BaseModel):
    """Registro de una foto subida (la subida binaria va a S3 vía pre-signed URL)."""
    s3_key: str | None = Field(default=None, max_length=500)
    device_timestamp: datetime | None = None


class EvidenciaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    usuario_id: str
    s3_url: str | None
    thumbnail_url: str | None
    sync_status: EvidenciaSyncStatus
    device_timestamp: datetime
    created_at: datetime


class HistorialOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    accion: str
    estado_anterior: str | None
    estado_nuevo: str | None
    detalle: str | None
    usuario_id: str | None = None
    nombre_usuario: str | None = None
    created_at: datetime


# ── Sincronización / Conflictos (Sección 8) ──────────────────────────────────
class ConflictoResolverIn(BaseModel):
    """Resolución manual: el Coordinador/Admin elige qué versión gana."""
    version_ganadora: str = Field(pattern="^(local|servidor)$")


# ── Notificaciones ───────────────────────────────────────────────────────────
class NotificacionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    evento: str
    titulo: str
    cuerpo: str | None
    leida: bool
    created_at: datetime


# ── GET /items/mis-items ─────────────────────────────────────────────────────
class MisItemOut(BaseModel):
    """Ítem asignado al usuario autenticado, con nombre del proyecto incluido."""
    id: str
    proyecto_id: str
    proyecto_nombre: str
    parent_item_id: str | None
    nivel_profundidad: int
    nombre: str
    descripcion: str | None
    asignado_a: str | None
    estado: ItemEstado
    fecha_limite: date | None


# ── GET /me ──────────────────────────────────────────────────────────────────
class MeUsuarioOut(BaseModel):
    """Datos del usuario autenticado. No incluye RUT (dato sensible, sin consumidor MVP)."""
    model_config = ConfigDict(from_attributes=True)
    id: str
    nombre_completo: str
    email: str
    es_super_admin: bool


class EmpresaMeOut(BaseModel):
    """Una empresa a la que pertenece el usuario autenticado (solo activas y no suspendidas)."""
    empresa_id: str
    empresa_nombre: str
    rol: Rol


class MeOut(BaseModel):
    """Respuesta completa de GET /me."""
    usuario: MeUsuarioOut
    empresas: list[EmpresaMeOut]


# ── Dashboard / Historial de proyecto (Coordinador — CTT-42) ─────────────────
class DashboardProyectoOut(BaseModel):
    id: str
    nombre: str
    estado: ProyectoEstado
    fecha_inicio: date | None
    fecha_fin_estimada: date | None
    total_items: int
    items_terminados: int
    pct_completo: float
    total_hojas: int
    hojas_terminadas: int
    pct_real: float


class ProyectoHistorialEntradaOut(BaseModel):
    item_id: str
    item_nombre: str
    accion: str
    estado_anterior: str | None
    estado_nuevo: str | None
    detalle: str | None
    usuario_id: str | None
    nombre_usuario: str | None
    created_at: datetime


# ── Audit log operativo (CTT-48) ──────────────────────────────────────────────
class AuditLogOut(BaseModel):
    id: str
    folio: int
    empresa_id: str
    actor_id: str | None
    actor_nombre: str
    actor_rol: str
    accion: str
    entidad_tipo: str
    entidad_id: str
    proyecto_id: str | None
    diff: dict | None
    detalle: str | None
    device_ts: datetime | None
    synced_offline: bool
    created_at: datetime
