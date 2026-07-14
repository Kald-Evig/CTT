/// residente_repository.dart — Acceso al backend para el Residente.
///
/// Transiciones de estado: online-first via TransicionService (CTT-36).
///   Si hay red: POST /items/{id}/transicion → resultado online.
///   Si no hay red: encola en Drift → resultado offline.
/// Lecturas y demás acciones (asignar, cerrar problema): Dio directo sin fallback.
library;

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/sync/resultado_transicion.dart';
import 'package:ctt_mobile/core/sync/transicion_service.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';

part 'residente_repository.g.dart';

@riverpod
ResidenteRepository residenteRepository(ResidenteRepositoryRef ref) =>
    ResidenteRepository(
      ref.watch(dioClientProvider),
      ref.watch(transicionServiceProvider),
    );

class ResidenteRepository {
  const ResidenteRepository(this._dio, this._transicionService);

  final Dio _dio;
  final TransicionService _transicionService;

  // ── Proyectos ────────────────────────────────────────────────────────────────

  Future<List<ProyectoResidente>> listarProyectos() =>
      _fetchList('/proyectos', ProyectoResidente.fromJson);

  // ── Ítems ────────────────────────────────────────────────────────────────────

  Future<List<ItemResidente>> listarItemsProyecto(
    String proyectoId, {
    String? estadoFiltro,
  }) {
    final params = <String, dynamic>{'proyecto_id': proyectoId};
    if (estadoFiltro != null) params['estado'] = estadoFiltro;
    return _fetchList('/items', ItemResidente.fromJson, queryParameters: params);
  }

  Future<ItemResidente> obtenerItem(String itemId) async {
    final resp = await _dio.get<Map<String, dynamic>>('/items/$itemId');
    return ItemResidente.fromJson(resp.data!);
  }

  Future<List<ComentarioItem>> listarComentarios(String itemId) =>
      _fetchList('/items/$itemId/comentarios', ComentarioItem.fromJson);

  Future<List<EvidenciaItem>> listarEvidencias(String itemId) =>
      _fetchList('/items/$itemId/evidencias', EvidenciaItem.fromJson);

  Future<List<EntradaHistorial>> listarHistorial(String itemId) =>
      _fetchList('/items/$itemId/historial', EntradaHistorial.fromJson);

  // ── Acciones ─────────────────────────────────────────────────────────────────

  /// Transición de estado online-first con fallback offline (CTT-36).
  /// Retorna [ResultadoTransicion] para que el llamador sepa qué ocurrió.
  Future<ResultadoTransicion> transicionarItem(
    String itemId,
    String nuevoEstado, {
    String? comentario,
    String? descripcionProblema,
  }) =>
      _transicionService.ejecutar(
        itemId: itemId,
        nuevoEstado: nuevoEstado,
        comentario: comentario,
        descripcionProblema: descripcionProblema,
      );

  Future<ItemResidente> cerrarProblema(String itemId) async {
    final resp = await _dio.post<Map<String, dynamic>>('/items/$itemId/cerrar-problema');
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

  Future<List<NotificacionResidente>> listarNotificaciones() =>
      _fetchList('/notificaciones', NotificacionResidente.fromJson);

  Future<void> marcarNotificacionLeida(String notifId) async {
    await _dio.post<void>('/notificaciones/$notifId/leer');
  }

  // ── Usuarios ─────────────────────────────────────────────────────────────────

  Future<List<UsuarioEmpresa>> listarUsuarios({List<String>? roles}) =>
      _fetchList(
        '/usuarios',
        UsuarioEmpresa.fromJson,
        queryParameters: (roles != null && roles.isNotEmpty)
            ? <String, dynamic>{'rol': roles}
            : null,
      );

  // ── Utilidades ───────────────────────────────────────────────────────────────

  Future<List<T>> _fetchList<T>(
    String url,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final resp = await _dio.get<List<dynamic>>(url, queryParameters: queryParameters);
    return (resp.data ?? []).cast<Map<String, dynamic>>().map(fromJson).toList();
  }
}
