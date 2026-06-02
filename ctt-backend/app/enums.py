"""
enums.py — Enumeraciones del dominio.

Cada Enum corresponde 1:1 a un campo ENUM del modelo de datos (Sección 5 del DDT).
Centralizarlos aquí evita "magic strings" dispersos y permite validación estricta
tanto en la BD como en los esquemas Pydantic.
"""

from enum import Enum


class Rol(str, Enum):
    """Roles a nivel de empresa (tabla empresa_usuario.rol — Sección 5.2).

    NOTA: 'super_admin' NO está aquí porque es un rol de PLATAFORMA, no de empresa.
    Se modela como flag booleano `es_super_admin` en la tabla usuarios, ya que el
    Super Admin no participa en operaciones de obra (Sección 2.1).
    """
    ADMIN = "admin"
    COORDINADOR = "coordinador"
    RESIDENTE = "residente"
    TRABAJADOR = "trabajador"


class EmpresaPlan(str, Enum):
    TRIAL = "trial"
    BASIC = "basic"
    PRO = "pro"


class EmpresaEstado(str, Enum):
    ACTIVO = "activo"
    SUSPENDIDO = "suspendido"
    TRIAL = "trial"


class UsuarioEstado(str, Enum):
    ACTIVO = "activo"
    INACTIVO = "inactivo"


class ProyectoEstado(str, Enum):
    ACTIVO = "activo"
    PAUSADO = "pausado"
    CERRADO = "cerrado"


class ItemEstado(str, Enum):
    """Estados de un ítem — máquina de estados de la Sección 6."""
    ABIERTO = "abierto"
    EN_PROGRESO = "en_progreso"
    PENDIENTE_REVISION = "pendiente_revision"
    TERMINADO = "terminado"
    PROBLEMA = "problema"


class ProblemaEstado(str, Enum):
    ABIERTO = "abierto"
    CERRADO = "cerrado"


class EvidenciaSyncStatus(str, Enum):
    PENDIENTE = "pendiente"
    SUBIDA = "subida"
    ERROR = "error"


class ConflictoEstado(str, Enum):
    PENDIENTE = "pendiente"
    RESUELTO = "resuelto"
