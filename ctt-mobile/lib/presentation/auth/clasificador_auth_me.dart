/// clasificador_auth_me.dart — Clasificación del error de GET /me (CTT-138).
///
/// El error que llega a `PerfilSesion.build` es un [DioException] cuyo `.error` ya
/// viene tipado por `ErrorInterceptor` (ExcepcionRed / ExcepcionNoAutorizado /
/// ExcepcionCuentaRevocada / ExcepcionSinPermiso). Este clasificador traduce ese
/// error a la decisión de auth: usar el fallback offline, ir a login por sesión
/// revocada, o tratarlo como error duro.
///
/// No reimplementa el clasificador del ciclo de sync (`ciclo_sync._clasificar`):
/// aquel mapea a `SenalSync` para la cola; este decide el estado de sesión. La
/// decisión "qué 403 es cuenta revocada" vive en `extraer_detalle_backend`
/// (`esCuentaRevocada403`), que la usa `ErrorInterceptor` para tipar la excepción.
library;

import 'package:dio/dio.dart';

import 'package:ctt_mobile/core/errors/exceptions.dart';

/// Resultado de clasificar un fallo de `/me`.
enum ErrorMe {
  /// Sin respuesta del servidor (red/timeout) → candidato a fallback offline.
  transporte,

  /// La sesión ya no es válida (401, o 403 con `code` de cuenta) → ir a login.
  revocada,

  /// 403 de permiso u otro error no clasificable como los anteriores.
  otro,
}

/// Clasifica el error de `/me`. Desempaqueta el `.error` del [DioException] (lo que
/// deja `ErrorInterceptor`); tolera recibir el error ya desempaquetado.
ErrorMe clasificarErrorMe(Object error) {
  final tipado = error is DioException ? error.error : error;
  if (tipado is ExcepcionRed) return ErrorMe.transporte;
  if (tipado is ExcepcionNoAutorizado) return ErrorMe.revocada; // 401
  if (tipado is ExcepcionCuentaRevocada) return ErrorMe.revocada; // 403 con code
  return ErrorMe.otro; // ExcepcionSinPermiso (403 de permiso) u otro
}
