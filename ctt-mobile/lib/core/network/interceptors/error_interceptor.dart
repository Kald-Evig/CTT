/// error_interceptor.dart — Interceptor de manejo de errores HTTP.
///
/// Convierte respuestas de error en excepciones tipadas para que los
/// repositorios las transformen en Failure. El logging solo ocurre en
/// modo debug — NUNCA loggear tokens ni payloads en release.
library;

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:ctt_mobile/core/config/environment.dart';
import 'package:ctt_mobile/core/errors/exceptions.dart';
import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';

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
        handler.reject(err.copyWith(error: const ExcepcionNoAutorizado()));
      case 403:
        handler.reject(err.copyWith(error: const ExcepcionSinPermiso()));
      case 422:
        // FastAPI devuelve validación Pydantic en el campo detail (lista de
        // errores). El parseo compartido resume los `msg` legibles (CTT-65).
        handler.reject(err.copyWith(
          error: ExcepcionValidacion(extraerDetalleBackend(err)),
        ),);
      case final int code when code >= 500:
        handler.reject(err.copyWith(
          error: ExcepcionServidor(
            'Error interno del servidor.',
            codigoHttp: code,
          ),
        ),);
      default:
        // Sin respuesta (timeout, sin conexión).
        if (err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError) {
          handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: const ExcepcionRed(
              'Sin conexión o tiempo de espera agotado.',
            ),
            type: err.type,
          ),);
        } else {
          handler.next(err);
        }
    }
  }
}
