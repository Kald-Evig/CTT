library;

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/domain/entities/coordinador_models.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';

part 'coordinador_repository.g.dart';

/// Excepción con el mensaje de error del backend para mostrar directamente en la UI.
class ErrorCoordinador implements Exception {
  const ErrorCoordinador(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

@riverpod
CoordinadorRepository coordinadorRepository(CoordinadorRepositoryRef ref) =>
    CoordinadorRepository(ref.watch(dioClientProvider));

class CoordinadorRepository {
  const CoordinadorRepository(this._dio);

  final Dio _dio;

  // ── Proyectos ────────────────────────────────────────────────────────────────

  Future<ProyectoCoordinador> crearProyecto({
    required String nombre,
    String? descripcion,
    String? ubicacionNombre,
    double? latitud,
    double? longitud,
    String? coordinadorPrincipalId,
    String? fechaInicio,
    String? fechaFinEstimada,
  }) async {
    final body = <String, dynamic>{'nombre': nombre};
    if (descripcion != null) body['descripcion'] = descripcion;
    if (ubicacionNombre != null) body['ubicacion_nombre'] = ubicacionNombre;
    if (latitud != null) body['latitud'] = latitud;
    if (longitud != null) body['longitud'] = longitud;
    if (coordinadorPrincipalId != null) {
      body['coordinador_principal_id'] = coordinadorPrincipalId;
    }
    if (fechaInicio != null) body['fecha_inicio'] = fechaInicio;
    if (fechaFinEstimada != null) body['fecha_fin_estimada'] = fechaFinEstimada;

    final resp = await _dio.post<Map<String, dynamic>>('/proyectos', data: body);
    return ProyectoCoordinador.fromJson(resp.data!);
  }

  // ── Ítems ────────────────────────────────────────────────────────────────────

  Future<ItemResidente> crearItem({
    required String proyectoId,
    required String nombre,
    String? parentItemId,
    String? descripcion,
    String? asignadoA,
    String? fechaLimite,
    double? duracionEstimadaHoras,
    int orden = 0,
  }) async {
    final body = <String, dynamic>{
      'proyecto_id': proyectoId,
      'nombre': nombre,
      'orden': orden,
    };
    if (parentItemId != null) body['parent_item_id'] = parentItemId;
    if (descripcion != null) body['descripcion'] = descripcion;
    if (asignadoA != null) body['asignado_a'] = asignadoA;
    if (fechaLimite != null) body['fecha_limite'] = fechaLimite;
    if (duracionEstimadaHoras != null) {
      body['duracion_estimada_horas'] = duracionEstimadaHoras;
    }

    try {
      final resp = await _dio.post<Map<String, dynamic>>('/items', data: body);
      return ItemResidente.fromJson(resp.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) throw ErrorCoordinador(_extraerDetalle(e));
      rethrow;
    }
  }

  // ── Conflictos ───────────────────────────────────────────────────────────────

  Future<List<ConflictoSync>> listarConflictos({String? estado}) async {
    final params = estado != null ? <String, dynamic>{'estado': estado} : null;
    final resp = await _dio.get<List<dynamic>>(
      '/sync/conflictos',
      queryParameters: params,
    );
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(ConflictoSync.fromJson)
        .toList();
  }

  /// Lanza [ErrorCoordinador] si el servidor devuelve 409 (conflicto ya resuelto
  /// o estado del ítem modificado desde que se registró el conflicto).
  Future<void> resolverConflicto(
    String conflictoId,
    String versionGanadora,
  ) async {
    try {
      await _dio.post<void>(
        '/sync/conflictos/$conflictoId/resolver',
        data: {'version_ganadora': versionGanadora},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) throw ErrorCoordinador(_extraerDetalle(e));
      rethrow;
    }
  }

  // ── Utilidades ───────────────────────────────────────────────────────────────

  static String _extraerDetalle(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) return detail;
    }
    return e.message ?? 'Error desconocido';
  }
}
