/// ultimo_contacto_interceptor.dart — Registra el último contacto 2xx (CTT-138).
///
/// Interceptor `onResponse` que, ante cualquier respuesta 2xx, guarda el instante en
/// SecureStorage como "último contacto con el servidor". Es el ÚNICO punto de éxito
/// común: se agrega al Dio interactivo y al de sync (ambos autenticados), así que
/// cubre tanto `/me` como las corridas de la cola, sin duplicar la lógica por isolate.
library;

import 'package:dio/dio.dart';

import 'package:ctt_mobile/core/security/secure_storage_service.dart';

class UltimoContactoInterceptor extends Interceptor {
  UltimoContactoInterceptor(this._storage);

  final SecureStorageService _storage;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final code = response.statusCode ?? 0;
    if (code >= 200 && code < 300) {
      // Fire-and-forget: no bloquea la cadena de respuesta.
      _storage.guardarUltimoContacto(DateTime.now().toUtc());
    }
    handler.next(response);
  }
}
