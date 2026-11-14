/// clasificacion_dio.dart — Clasificación CANÓNICA de una [DioException] por presencia
/// de respuesta (CTT-142 fase A).
///
/// Fuente ÚNICA de la decisión "¿esto es una falla sin respuesta y, si lo es, de red o
/// interna?". La consumen los TRES caminos de red: la cola (`ciclo_sync._clasificar`),
/// el rescate (`rescate_service`) y el interactivo (`error_interceptor`). `DioExceptionType`
/// y los tipos de `dart:io` aparecen SOLO en este archivo — ningún camino vuelve a listar
/// tipos de transporte por su cuenta.
///
/// Criterio base: una falla "sin respuesta" ⇔ `e.response == null`. Entre las sin respuesta
/// se distingue TRANSPORTE (red) de INTERNA (del cliente), porque el interactivo las trata
/// distinto: transporte → `ExcepcionRed` → fallback offline (CTT-138); interna → error duro.
///
/// Por qué `unknown` se desambigua por el error envuelto (CTT-142 fase A, verificado en
/// dio 5.9.2): el adapter IO solo convierte `SocketException` en `connectionError` durante
/// la APERTURA de la conexión (io_adapter.dart:82-136). Si la conexión se corta DESPUÉS de
/// abrirse —en pleno envío o recepción, el caso típico de 3G débil en obra— la
/// `SocketException`/`HttpException` escapa sin capturar y dio la entrega como
/// `DioExceptionType.unknown` con `response == null` (assureDioException → type por defecto).
/// Ese `unknown` ES una falla de red y debe habilitar el fallback offline. En cambio un
/// `unknown` que envuelve otra cosa (p. ej. `PlatformException` de una falla del Keystore en
/// un interceptor, o `FormatException` del serializer) es interno y NO debe esconderse como
/// falta de red.
///
/// `TlsException`/`HandshakeException` (problema de certificado) se clasifican como INTERNA,
/// no como red: un certificado inválido no debe disfrazarse de "sin conexión". Como no son
/// `SocketException` ni `HttpException`, caen naturalmente en la rama interna.
library;

import 'dart:io' show HttpException, SocketException;

import 'package:dio/dio.dart';

/// Clase canónica de una [DioException] según si hubo respuesta del servidor.
enum ClaseFallaDio {
  /// El servidor respondió (hay status HTTP). `e.response != null`.
  conRespuesta,

  /// No hubo respuesta y la causa es de TRANSPORTE (red): timeouts de conexión/envío/
  /// recepción, `connectionError`, o un `unknown` que envuelve `SocketException`/
  /// `HttpException` (corte de red en mitad del request).
  sinRespuestaTransporte,

  /// No hubo respuesta y la causa es INTERNA del cliente, no de la red: un `unknown` que
  /// envuelve `PlatformException`/`FormatException`/`TlsException`/`HandshakeException` u
  /// otro; `cancel`; `badCertificate`.
  sinRespuestaInterna,
}

/// Clasifica [e] en una [ClaseFallaDio]. Es el ÚNICO lugar que inspecciona
/// [DioExceptionType] y los tipos de `dart:io`.
ClaseFallaDio clasificarFallaDio(DioException e) {
  if (e.response != null) return ClaseFallaDio.conRespuesta;
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return ClaseFallaDio.sinRespuestaTransporte;
    case DioExceptionType.unknown:
      // Desambiguar por el error envuelto: red (Socket/Http) vs interno (todo lo demás).
      final err = e.error;
      if (err is SocketException || err is HttpException) {
        return ClaseFallaDio.sinRespuestaTransporte;
      }
      return ClaseFallaDio.sinRespuestaInterna;
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
      return ClaseFallaDio.sinRespuestaInterna;
    case DioExceptionType.badResponse:
      // badResponse SIEMPRE trae response → inalcanzable por el guard de arriba. Se deja
      // explícito para que el switch sea exhaustivo sin `default`.
      return ClaseFallaDio.conRespuesta;
  }
}
