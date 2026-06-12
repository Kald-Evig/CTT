/// auth_interceptor.dart — Interceptor de autenticación JWT.
///
/// Lee el token desde SecureStorageService y lo adjunta a cada request.
/// También agrega el header X-Empresa-Id cuando el usuario pertenece a
/// múltiples empresas (flujo multi-tenant del backend).

import 'package:dio/dio.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage);

  final SecureStorageService _storage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.obtenerToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    final empresaId = await _storage.obtenerEmpresaId();
    if (empresaId != null) {
      options.headers['X-Empresa-Id'] = empresaId;
    }

    handler.next(options);
  }
}
