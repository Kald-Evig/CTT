library;

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';
import 'package:ctt_mobile/core/network/red_helpers.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';

part 'admin_repository.g.dart';

class ErrorAdmin implements Exception {
  const ErrorAdmin(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

typedef UsuarioCreado = ({
  UsuarioEmpresa usuario,
  String? resetLink,
  bool resetLinkPendiente,
});

@riverpod
AdminRepository adminRepository(AdminRepositoryRef ref) =>
    AdminRepository(ref.watch(dioClientProvider));

class AdminRepository {
  const AdminRepository(this._dio);

  final Dio _dio;

  Future<List<UsuarioEmpresa>> listarUsuarios({
    bool incluirInactivos = false,
  }) =>
      fetchList(
        _dio,
        '/usuarios',
        UsuarioEmpresa.fromJson,
        queryParameters: incluirInactivos
            ? <String, dynamic>{'incluir_inactivos': true}
            : null,
      );

  Future<UsuarioCreado> crearUsuario({
    required String nombre,
    required String email,
    required String rol,
    String? rut,
    String? telefono,
  }) async {
    final body = <String, dynamic>{
      'nombre_completo': nombre,
      'email': email,
      'rol': rol,
    };
    if (rut != null && rut.isNotEmpty) body['rut'] = rut;
    if (telefono != null && telefono.isNotEmpty) body['telefono'] = telefono;

    try {
      final resp =
          await _dio.post<Map<String, dynamic>>('/usuarios', data: body);
      final data = resp.data!;
      final usuario = UsuarioEmpresa.fromJson(data);
      return (
        usuario: usuario,
        resetLink: data['reset_link'] as String?,
        resetLinkPendiente: (data['reset_link_pendiente'] as bool?) ?? false,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != null && code >= 400 && code < 500) {
        throw ErrorAdmin(extraerDetalleBackend(e));
      }
      rethrow;
    }
  }

  Future<void> desactivarUsuario(String usuarioId) async {
    try {
      await _dio.patch<void>(
        '/usuarios/$usuarioId/estado',
        data: {'estado': 'inactivo'},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != null) {
        throw ErrorAdmin(extraerDetalleBackend(e));
      }
      rethrow;
    }
  }

  Future<void> reactivarUsuario(String usuarioId) async {
    try {
      await _dio.patch<void>(
        '/usuarios/$usuarioId/estado',
        data: {'estado': 'activo'},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != null) {
        throw ErrorAdmin(extraerDetalleBackend(e));
      }
      rethrow;
    }
  }

  Future<void> cambiarRol(String usuarioId, String rol) async {
    try {
      await _dio.patch<void>(
        '/usuarios/$usuarioId/rol',
        data: {'rol': rol},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != null) {
        throw ErrorAdmin(extraerDetalleBackend(e));
      }
      rethrow;
    }
  }

  Future<void> cerrarProyecto(String proyectoId) async {
    try {
      await _dio.post<void>('/proyectos/$proyectoId/cerrar');
    } on DioException catch (e) {
      if (e.response?.statusCode != null) {
        throw ErrorAdmin(extraerDetalleBackend(e));
      }
      rethrow;
    }
  }
}
