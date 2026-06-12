/// error_interceptor.dart — Interceptor de manejo de errores HTTP.
///
/// Convierte respuestas de error en excepciones tipadas para que los
/// repositorios las transformen en Failure. El logging solo ocurre en
/// modo debug — NUNCA loggear tokens ni payloads en release.

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:ctt_mobile/core/config/environment.dart';
import 'package:ctt_mobile/core/errors/exceptions.dart';

class ErrorInterceptor extends Interceptor {
  ErrorInterceptor(this._logger, {required this.alCerrarSesion});

  final Logger _logger;

  /// Callback que dispara logout cuando el token expira (HTTP 401).
  final Future<void> Function() alCerrarSesion;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final codigoHttp = err.response?.statusCode;

    if (Entorno.esDebug) {
      // Solo en debug — nunca exponer tokens en producción.
      _logger.w(
        'HTTP $codigoHttp en ${err.requestOptions.path}',
        error: err.message,
      );
    }

    switch (codigoHttp) {
      case 401:
        // Token expirado: desloguear y limpiar sesión.
        alCerrarSesion();
        handler.reject(DioException(
          requestOptions: err.requestOptions,
          error: const ExcepcionNoAutorizado(),
          type: DioExceptionType.badResponse,
        ));
      case 403:
        handler.reject(DioException(
          requestOptions: err.requestOptions,
          error: const ExcepcionSinPermiso(),
          type: DioExceptionType.badResponse,
        ));
      case 422:
        // FastAPI devuelve validación Pydantic en detail.
        final detalle = err.response?.data?['detail']?.toString() ??
            'Datos inválidos.';
        handler.reject(DioException(
          requestOptions: err.requestOptions,
          error: ExcepcionValidacion(detalle),
          type: DioExceptionType.badResponse,
        ));
      case >= 500:
        handler.reject(DioException(
          requestOptions: err.requestOptions,
          error: ExcepcionServidor(
            'Error interno del servidor.',
            codigoHttp: codigoHttp,
          ),
          type: DioExceptionType.badResponse,
        ));
      default:
        // Sin respuesta (timeout, sin conexión).
        if (err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError) {
          handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: const ExcepcionRed('Sin conexión o tiempo de espera agotado.'),
            type: err.type,
          ));
        } else {
          handler.next(err);
        }
    }
  }
}
