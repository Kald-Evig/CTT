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


class IdempotenciaEstado(str, Enum):
    """Estado de una clave de idempotencia (CTT-105)."""
    EN_PROCESO = "en_proceso"   # reserva tomada, endpoint todavía en ejecución
    COMPLETADO = "completado"   # respuesta definitiva persistida, lista para replay


class RescateEstado(str, Enum):
    """Estado de revisión de una fila rescatada a cuarentena (CTT-130 fase 4b)."""
    PENDIENTE_REVISION = "pendiente_revision"  # esperando revisión de un coordinador
    YA_APLICADA = "ya_aplicada"                # su idempotency_key ya se aplicó (CTT-105); no reaplicar


class RechazoMotivo(str, Enum):
    """Causa (gruesa) de un rechazo determinista persistido en sync_rechazos (CTT-103).

    No revela más que el código HTTP que la acompaña: `inexistente`/`no_autorizado`
    emparejan 404/403 que el cliente ya distingue. La causa EXACTA (qué rama disparó
    el 404, qué regla de la máquina de estados) vive en `detalle_interno`, no acá.
    """
    TRANSICION_INVALIDA = "transicion_invalida"  # 409: la máquina de estados rechazó la transición
    NO_AUTORIZADO = "no_autorizado"              # 403: el actor no puede operar este ítem
    INEXISTENTE = "inexistente"                  # 404: el ítem no existe / no es visible para el actor


class RechazoResolucion(str, Enum):
    """Estado de resolución de un rechazo por parte del coordinador (CTT-134)."""
    PENDIENTE = "pendiente"                                # sin revisar
    REAPLICADO = "reaplicado"                              # el coordinador reaplicó el cambio
    DESCARTADO_POR_COORDINADOR = "descartado_por_coordinador"  # el coordinador lo descartó
