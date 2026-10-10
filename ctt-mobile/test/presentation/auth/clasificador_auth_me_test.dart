/// clasificador_auth_me_test.dart — CTT-138.
///
/// clasificarErrorMe mapea el error tipado de /me (lo que deja ErrorInterceptor en
/// DioException.error) a la decisión de auth: transporte | revocada | otro.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/errors/exceptions.dart';
import 'package:ctt_mobile/presentation/auth/clasificador_auth_me.dart';

DioException _conError(Object error) => DioException(
      requestOptions: RequestOptions(path: '/me'),
      error: error,
      type: DioExceptionType.badResponse,
    );

void main() {
  test('ExcepcionRed (red/timeout) → transporte', () {
    expect(clasificarErrorMe(_conError(const ExcepcionRed())), ErrorMe.transporte);
  });

  test('401 (ExcepcionNoAutorizado) → revocada', () {
    expect(
      clasificarErrorMe(_conError(const ExcepcionNoAutorizado())),
      ErrorMe.revocada,
    );
  });

  test('403 con code (ExcepcionCuentaRevocada) → revocada', () {
    expect(
      clasificarErrorMe(
          _conError(const ExcepcionCuentaRevocada('usuario_deshabilitado'))),
      ErrorMe.revocada,
    );
  });

  test('403 de permiso (ExcepcionSinPermiso) → otro', () {
    expect(
      clasificarErrorMe(_conError(const ExcepcionSinPermiso())),
      ErrorMe.otro,
    );
  });

  test('tolera el error ya desempaquetado (no envuelto en DioException)', () {
    expect(clasificarErrorMe(const ExcepcionRed()), ErrorMe.transporte);
  });
}
