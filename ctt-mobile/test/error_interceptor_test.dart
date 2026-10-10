/// error_interceptor_test.dart — CTT-102 + CTT-138.
///
/// CTT-102: el ErrorInterceptor NO descarta `response` al traducir un error HTTP a
/// excepción tipada (el defecto dejaba a ciclo_sync sin `statusCode`).
/// CTT-138: el 403 deja de descartar el body — un `detail.code` de cuenta
/// (usuario_deshabilitado / tenant_suspendido) se tipa como ExcepcionCuentaRevocada
/// (sesión revocada), y un 403 sin ese code sigue siendo ExcepcionSinPermiso.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:ctt_mobile/core/errors/exceptions.dart';
import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';
import 'package:ctt_mobile/core/network/interceptors/error_interceptor.dart';

/// Adapter que responde un [body]/[status] fijo, sin tocar la red.
class _AdapterFijo implements HttpClientAdapter {
  _AdapterFijo(this.body, this.status);
  final String body;
  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

Dio _dioCon(String body, int status) =>
    Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _AdapterFijo(body, status)
      ..interceptors.add(
        ErrorInterceptor(Logger(level: Level.off), alCerrarSesion: () async {}),
      );

Future<DioException> _capturar(Dio dio) async {
  try {
    await dio.get<void>('/me');
    fail('la request debía fallar');
  } on DioException catch (e) {
    return e;
  }
}

void main() {
  test('403 con body: response sobrevive al ErrorInterceptor (CTT-102)', () async {
    final e = await _capturar(
      _dioCon('{"detail":"Este ítem no está asignado a usted."}', 403),
    );

    // 1) El statusCode sobrevive: ciclo_sync lo lee de e.response?.statusCode.
    expect(e.response?.statusCode, 403);
    // 2) El motivo es el string del backend, NO el genérico 'Error de red'.
    expect(extraerDetalleBackend(e), 'Este ítem no está asignado a usted.');
    // 3) 403 de permiso (detail String, sin code) → ExcepcionSinPermiso.
    expect(e.error, isA<ExcepcionSinPermiso>());
  });

  test('403 con detail.code de cuenta → ExcepcionCuentaRevocada (CTT-138)', () async {
    final e = await _capturar(
      _dioCon(
        '{"detail":{"code":"usuario_deshabilitado","mensaje":"Cuenta deshabilitada."}}',
        403,
      ),
    );

    expect(e.response?.statusCode, 403);
    expect(e.error, isA<ExcepcionCuentaRevocada>());
    expect((e.error as ExcepcionCuentaRevocada).code, 'usuario_deshabilitado');
  });

  test('403 con detail.code NO de cuenta → ExcepcionSinPermiso (CTT-138)', () async {
    final e = await _capturar(
      _dioCon('{"detail":{"code":"ALGO_RARO"}}', 403),
    );

    expect(e.error, isA<ExcepcionSinPermiso>());
    expect(e.error, isNot(isA<ExcepcionCuentaRevocada>()));
  });

  test('esCuentaRevocada403 sobre bodies fabricados (CTT-138)', () {
    DioException err403(Object? data) {
      final ro = RequestOptions(path: '/me');
      return DioException(
        requestOptions: ro,
        response: Response<dynamic>(
            requestOptions: ro, statusCode: 403, data: data),
        type: DioExceptionType.badResponse,
      );
    }

    expect(
      esCuentaRevocada403(err403({
        'detail': {'code': 'tenant_suspendido'}
      })),
      isTrue,
    );
    expect(
      esCuentaRevocada403(err403({
        'detail': {'code': 'otro'}
      })),
      isFalse,
    );
    // detail String (403 de permiso) → sin code → false.
    expect(esCuentaRevocada403(err403({'detail': 'sin permiso'})), isFalse);
  });
}
