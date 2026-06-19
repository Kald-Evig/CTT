"""
schemas.py — Esquemas Pydantic (v2) de entrada y salida.

Separan el contrato de la API del modelo ORM. Los modelos *Out usan
`from_attributes=True` para construirse directamente desde objetos SQLAlchemy.
"""

import re
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.enums import (
    EmpresaPlan, EvidenciaSyncStatus, ItemEstado, ProyectoEstado, Rol,
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
    estado: ProyectoEstado
    fecha_inicio: date | None
    fecha_fin_estimada: date | None


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
