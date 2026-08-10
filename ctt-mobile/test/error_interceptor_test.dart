/// error_interceptor_test.dart — CTT-102.
///
/// Verifica que el ErrorInterceptor NO descarta `response` al traducir un error
/// HTTP a excepción tipada. El defecto original (crear una DioException nueva sin
/// `response`) dejaba a ciclo_sync sin `statusCode`, clasificando un 403 permanente
/// como error de red transitorio. El fix usa `err.copyWith(error: ...)`, que
/// preserva `response` vía `?? this.response`.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:ctt_mobile/core/errors/exceptions.dart';
import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';
import 'package:ctt_mobile/core/network/interceptors/error_interceptor.dart';

/// Adapter que responde 403 con el body real del backend, sin tocar la red.
class _Adapter403 implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"detail":"Este ítem no está asignado a usted."}',
      403,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('403 con body: response sobrevive al ErrorInterceptor (CTT-102)', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _Adapter403()
      ..interceptors.add(
        ErrorInterceptor(
          Logger(level: Level.off),
          alCerrarSesion: () async {},
        ),
      );

    DioException? capturada;
    try {
      await dio.post<void>('/items/x/transicion');
    } on DioException catch (e) {
      capturada = e;
    }

    // Debe haber fallado (403 no es 2xx).
    expect(capturada, isNotNull);

    // 1) El statusCode sobrevive: ciclo_sync lo lee de e.response?.statusCode.
    expect(capturada!.response?.statusCode, 403);

    // 2) El motivo es el string del backend, NO el genérico 'Error de red'.
    final motivo = extraerDetalleBackend(capturada);
    expect(motivo, 'Este ítem no está asignado a usted.');
    expect(motivo, isNot('Error de red'));

    // 3) La excepción tipada se conserva (no se rompió la traducción).
    expect(capturada.error, isA<ExcepcionSinPermiso>());
  });
}
