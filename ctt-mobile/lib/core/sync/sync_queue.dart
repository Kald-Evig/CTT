/// sync_queue.dart — Modelo de la cola de sincronización offline-first.
///
/// Todos los cambios del usuario se registran aquí PRIMERO (en Drift),
/// antes de intentar enviarlos al API. Garantiza que ningún cambio se pierde
/// aunque la conexión caiga a mitad de una operación.

import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

/// Representa un cambio pendiente de sincronizar con el servidor.
class SyncPendiente {
  const SyncPendiente({
    required this.id,
    required this.tipoEntidad,
    required this.entidadId,
    required this.accion,
    required this.payload,
    required this.timestampDispositivo,
    required this.dispositivoId,
    this.reintentos = 0,
    this.estado = EstadoSyncLocal.pendiente,
    this.ultimoError,
  });

  /// UUID local generado en el dispositivo.
  final String id;

  /// Tipo de entidad afectada, p.ej. 'item', 'comentario', 'evidencia'.
  final String tipoEntidad;

  /// ID de la entidad en el servidor (o UUID local si aún no existe en servidor).
  final String entidadId;

  /// Acción realizada, p.ej. 'cambio_estado', 'agregar_comentario', 'subir_foto'.
  final String accion;

  /// Datos del cambio serializados como JSON string.
  /// Corresponde al body que se enviará al endpoint del API.
  final String payload;

  /// Timestamp del dispositivo cuando se realizó el cambio (UTC).
  /// El backend usa este valor para resolver conflictos (Sección 8).
  final DateTime timestampDispositivo;

  /// Identificador único del dispositivo (generado una vez en instalación).
  final String dispositivoId;

  /// Número de intentos de envío fallidos. Usado para backoff exponencial.
  final int reintentos;

  /// Estado actual en la cola.
  final EstadoSyncLocal estado;

  /// Mensaje del último error para diagnóstico (no se muestra al usuario final).
  final String? ultimoError;

  SyncPendiente copyWith({
    EstadoSyncLocal? estado,
    int? reintentos,
    String? ultimoError,
  }) =>
      SyncPendiente(
        id: id,
        tipoEntidad: tipoEntidad,
        entidadId: entidadId,
        accion: accion,
        payload: payload,
        timestampDispositivo: timestampDispositivo,
        dispositivoId: dispositivoId,
        reintentos: reintentos ?? this.reintentos,
        estado: estado ?? this.estado,
        ultimoError: ultimoError ?? this.ultimoError,
      );
}

/// Acciones conocidas de sync. Usar constantes en vez de magic strings.
abstract final class AccionSync {
  static const cambioEstadoItem = 'cambio_estado_item';
  static const agregarComentario = 'agregar_comentario';
  static const subirFoto = 'subir_foto';
  static const cerrarProblema = 'cerrar_problema';
  static const asignarItem = 'asignar_item';
}

/// Tipos de entidad conocidos para la cola.
abstract final class TipoEntidad {
  static const item = 'item';
  static const comentario = 'comentario';
  static const evidencia = 'evidencia';
  static const problema = 'problema';
}
