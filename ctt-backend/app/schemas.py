"""
schemas.py — Esquemas Pydantic (v2) de entrada y salida.

Separan el contrato de la API del modelo ORM. Los modelos *Out usan
`from_attributes=True` para construirse directamente desde objetos SQLAlchemy.
"""

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.enums import (
    EmpresaPlan, ItemEstado, ProyectoEstado, Rol,
)


# ── Empresas ─────────────────────────────────────────────────────────────────
class EmpresaCreate(BaseModel):
    nombre: str
    rut_empresa: str
    email_contacto: EmailStr
    plan: EmpresaPlan = EmpresaPlan.TRIAL


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
    nombre_completo: str
    rut: str | None = None
    email: EmailStr
    telefono: str | None = None
    rol: Rol  # rol con el que se crea en la empresa activa


class UsuarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    nombre_completo: str
    rut: str | None
    email: str
    estado: str


# ── Proyectos ────────────────────────────────────────────────────────────────
class ProyectoCreate(BaseModel):
    nombre: str
    descripcion: str | None = None
    ubicacion_nombre: str | None = None
    latitud: float | None = None
    longitud: float | None = None
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
    nombre: str
    descripcion: str | None = None
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
    estado: ItemEstado
    fecha_limite: date | None


class AsignarItemIn(BaseModel):
    usuario_id: str


class TransicionIn(BaseModel):
    """Cambio de estado de un ítem (Sección 6)."""
    nuevo_estado: ItemEstado
    comentario: str | None = None              # obligatorio en rechazo
    descripcion_problema: str | None = None     # obligatorio al marcar problema


class ComentarioIn(BaseModel):
    texto: str = Field(min_length=1)


class EvidenciaIn(BaseModel):
    """Registro de una foto subida (la subida binaria va a S3 vía pre-signed URL)."""
    s3_key: str | None = None
    device_timestamp: datetime | None = None


class HistorialOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    accion: str
    estado_anterior: str | None
    estado_nuevo: str | None
    detalle: str | None
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
