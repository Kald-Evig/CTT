/// residente_repository.dart — Acceso online directo al backend para el Residente.
///
/// Sin offline-first: el Residente trabaja con señal (DDT §7.2).
/// Todas las operaciones van directo al backend vía Dio; ninguna toca Drift.
library;

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';

part 'residente_repository.g.dart';

@riverpod
ResidenteRepository residenteRepository(ResidenteRepositoryRef ref) =>
    ResidenteRepository(ref.watch(dioClientProvider));

class ResidenteRepository {
  const ResidenteRepository(this._dio);

  final Dio _dio;

  // ── Proyectos ────────────────────────────────────────────────────────────────

  Future<List<ProyectoResidente>> listarProyectos() async {
    final resp = await _dio.get<List<dynamic>>('/proyectos');
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(ProyectoResidente.fromJson)
        .toList();
  }

  // ── Ítems ────────────────────────────────────────────────────────────────────

  Future<List<ItemResidente>> listarItemsProyecto(
    String proyectoId, {
    String? estadoFiltro,
  }) async {
    final params = <String, dynamic>{'proyecto_id': proyectoId};
    if (estadoFiltro != null) params['estado'] = estadoFiltro;
    final resp = await _dio.get<List<dynamic>>(
      '/items',
      queryParameters: params,
    );
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(ItemResidente.fromJson)
        .toList();
  }

  Future<ItemResidente> obtenerItem(String itemId) async {
    final resp = await _dio.get<Map<String, dynamic>>('/items/$itemId');
    return ItemResidente.fromJson(resp.data!);
  }

  Future<List<ComentarioItem>> listarComentarios(String itemId) async {
    final resp =
        await _dio.get<List<dynamic>>('/items/$itemId/comentarios');
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(ComentarioItem.fromJson)
        .toList();
  }

  Future<List<EvidenciaItem>> listarEvidencias(String itemId) async {
    final resp =
        await _dio.get<List<dynamic>>('/items/$itemId/evidencias');
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(EvidenciaItem.fromJson)
        .toList();
  }

  Future<List<EntradaHistorial>> listarHistorial(String itemId) async {
    final resp =
        await _dio.get<List<dynamic>>('/items/$itemId/historial');
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(EntradaHistorial.fromJson)
        .toList();
  }

  // ── Acciones ─────────────────────────────────────────────────────────────────

  /// Transición de estado directa al backend (sin cola offline).
  Future<ItemResidente> transicionarItem(
    String itemId,
    String nuevoEstado, {
    String? comentario,
    String? descripcionProblema,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/items/$itemId/transicion',
      data: {
        'nuevo_estado': nuevoEstado,
        if (comentario != null) 'comentario': comentario,
        if (descripcionProblema != null)
          'descripcion_problema': descripcionProblema,
      },
    );
    return ItemResidente.fromJson(resp.data!);
  }

  Future<ItemResidente> cerrarProblema(String itemId) async {
    final resp = await _dio
        .post<Map<String, dynamic>>('/items/$itemId/cerrar-problema');
    return ItemResidente.fromJson(resp.data!);
  }

  Future<ItemResidente> asignarItem(String itemId, String usuarioId) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/items/$itemId/asignar',
      data: {'usuario_id': usuarioId},
    );
    return ItemResidente.fromJson(resp.data!);
  }

  // ── Notificaciones ───────────────────────────────────────────────────────────

  Future<List<NotificacionResidente>> listarNotificaciones() async {
    final resp = await _dio.get<List<dynamic>>('/notificaciones');
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(NotificacionResidente.fromJson)
        .toList();
  }

  Future<void> marcarNotificacionLeida(String notifId) async {
    await _dio.post<void>('/notificaciones/$notifId/leer');
  }

  // ── Usuarios (selector de asignación) ────────────────────────────────────────

  Future<List<UsuarioEmpresa>> listarUsuarios() async {
    final resp = await _dio.get<List<dynamic>>('/usuarios');
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(UsuarioEmpresa.fromJson)
        .toList();
  }
}
