/// clasificacion_dio_test.dart — CTT-142 fase A: clasificador único de "falla sin
/// respuesta" (core/network/clasificacion_dio.dart) + su efecto en el camino interactivo.
///
/// Tabla completa DioExceptionType × error envuelto, la desambiguación de `unknown`
/// (SocketException/HttpException = red; PlatformException/FormatException/HandshakeException
/// = interna), y la integración con dio 5.9.2 cuando el adapter lanza una SocketException
/// DESPUÉS de aceptar la conexión (durante el envío): dio la entrega como `unknown` con
/// `response == null` y el helper la clasifica como transporte.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:ctt_mobile/core/errors/exceptions.dart';
import 'package:ctt_mobile/core/network/clasificacion_dio.dart';
import 'package:ctt_mobile/core/network/interceptors/error_interceptor.dart';
import 'package:ctt_mobile/presentation/auth/clasificador_auth_me.dart';

DioException _sinResp(DioExceptionType type, {Object? error}) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      error: error,
    );

DioException _conResp(int status, {DioExceptionType type = DioExceptionType.badResponse}) {
  final ro = RequestOptions(path: '/x');
  return DioException(
    requestOptions: ro,
    type: type,
    response: Response<dynamic>(requestOptions: ro, statusCode: status),
  );
}

/// Adapter que, tras drenar el cuerpo (acepta la conexión y empieza a enviar), lanza
/// [_aLanzar]. Un objeto que NO es DioException lo envuelve dio en `unknown` (assureDioException).
class _AdapterLanza implements HttpClientAdapter {
  _AdapterLanza(this._aLanzar);
  final Object _aLanzar;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      await requestStream.drain<void>(); // "acepta" y consume el envío antes de cortar
    }
    throw _aLanzar;
  }

  @override
  void close({bool force = false}) {}
}

/// Pasa [aLanzar] por un Dio con ErrorInterceptor (camino interactivo) y devuelve la
/// DioException resultante (tras la traducción del interceptor).
Future<DioException> _viaInteractivo(Object aLanzar, {Object? data}) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = _AdapterLanza(aLanzar)
    ..interceptors.add(
      ErrorInterceptor(Logger(level: Level.off), alCerrarSesion: () async {}),
    );
  try {
    if (data != null) {
      await dio.post<void>('/x', data: data);
    } else {
      await dio.get<void>('/me');
    }
    fail('la request debía fallar');
  } on DioException catch (e) {
    return e;
  }
}

/// Pasa [aLanzar] por un Dio SIN ErrorInterceptor (crudo) y devuelve la DioException tal
/// como la envuelve dio — para observar el `type`/`response` reales antes de traducir.
Future<DioException> _viaAdapterCrudo(Object aLanzar, {Object? data}) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = _AdapterLanza(aLanzar);
  try {
    if (data != null) {
      await dio.post<void>('/x', data: data);
    } else {
      await dio.get<void>('/me');
    }
    fail('la request debía fallar');
  } on DioException catch (e) {
    return e;
  }
}

void main() {
  group('clasificarFallaDio — tabla canónica', () {
    test('timeouts y connectionError → sinRespuestaTransporte', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        expect(
          clasificarFallaDio(_sinResp(t)),
          ClaseFallaDio.sinRespuestaTransporte,
          reason: '$t debe ser transporte',
        );
      }
    });

    test('unknown + SocketException/HttpException → sinRespuestaTransporte', () {
      expect(
        clasificarFallaDio(
          _sinResp(DioExceptionType.unknown,
              error: const SocketException('Connection reset by peer'),),
        ),
        ClaseFallaDio.sinRespuestaTransporte,
      );
      expect(
        clasificarFallaDio(
          _sinResp(DioExceptionType.unknown,
              error: const HttpException('Connection closed before full header'),),
        ),
        ClaseFallaDio.sinRespuestaTransporte,
      );
    });

    test('unknown + PlatformException/FormatException/HandshakeException/otro/null → interna', () {
      expect(
        clasificarFallaDio(
          _sinResp(DioExceptionType.unknown,
              error: PlatformException(code: 'keystore_error'),),
        ),
        ClaseFallaDio.sinRespuestaInterna,
        reason: 'falla del Keystore no es red',
      );
      expect(
        clasificarFallaDio(
          _sinResp(DioExceptionType.unknown, error: const FormatException('bad json')),
        ),
        ClaseFallaDio.sinRespuestaInterna,
      );
      expect(
        clasificarFallaDio(
          _sinResp(DioExceptionType.unknown, error: const HandshakeException('tls')),
        ),
        ClaseFallaDio.sinRespuestaInterna,
        reason: 'un problema de certificado NO se esconde como falta de red',
      );
      expect(
        clasificarFallaDio(_sinResp(DioExceptionType.unknown, error: Exception('otro'))),
        ClaseFallaDio.sinRespuestaInterna,
      );
      expect(
        clasificarFallaDio(_sinResp(DioExceptionType.unknown)),
        ClaseFallaDio.sinRespuestaInterna,
        reason: 'unknown sin error envuelto → interna',
      );
    });

    test('cancel y badCertificate → sinRespuestaInterna', () {
      expect(clasificarFallaDio(_sinResp(DioExceptionType.cancel)),
          ClaseFallaDio.sinRespuestaInterna,);
      expect(clasificarFallaDio(_sinResp(DioExceptionType.badCertificate)),
          ClaseFallaDio.sinRespuestaInterna,);
    });

    test('badResponse (response != null) → conRespuesta', () {
      expect(clasificarFallaDio(_conResp(409)), ClaseFallaDio.conRespuesta);
      expect(clasificarFallaDio(_conResp(500)), ClaseFallaDio.conRespuesta);
    });

    test('response != null manda aunque el type sea unknown', () {
      expect(
        clasificarFallaDio(_conResp(503, type: DioExceptionType.unknown)),
        ClaseFallaDio.conRespuesta,
      );
    });
  });

  group('interactivo (ErrorInterceptor) → ExcepcionRed/crudo → clasificarErrorMe', () {
    test('sendTimeout → ExcepcionRed → ErrorMe.transporte (cambio a, CTT-142)', () async {
      final e = await _viaInteractivo(
        DioException.sendTimeout(
          timeout: const Duration(seconds: 15),
          requestOptions: RequestOptions(path: '/me'),
        ),
      );
      expect(e.error, isA<ExcepcionRed>());
      expect(clasificarErrorMe(e), ErrorMe.transporte);
    });

    test('unknown + SocketException → ExcepcionRed → ErrorMe.transporte (cambio c, CTT-142)',
        () async {
      final e = await _viaInteractivo(const SocketException('reset'));
      expect(e.type, DioExceptionType.unknown, reason: 'dio envuelve el Socket en unknown');
      expect(e.response, isNull);
      expect(e.error, isA<ExcepcionRed>());
      expect(clasificarErrorMe(e), ErrorMe.transporte);
    });

    test('unknown + HttpException → ExcepcionRed → ErrorMe.transporte', () async {
      final e = await _viaInteractivo(const HttpException('closed'));
      expect(e.error, isA<ExcepcionRed>());
      expect(clasificarErrorMe(e), ErrorMe.transporte);
    });

    test('unknown + PlatformException (Keystore) → crudo → ErrorMe.otro (regresión CTT-138)',
        () async {
      final e = await _viaInteractivo(PlatformException(code: 'keystore_error'));
      expect(e.error, isA<PlatformException>(),
          reason: 'NO se convierte en ExcepcionRed: no abriría sesión offline por un error interno',);
      expect(e.error, isNot(isA<ExcepcionRed>()));
      expect(clasificarErrorMe(e), ErrorMe.otro);
    });

    test('unknown + FormatException → crudo → ErrorMe.otro', () async {
      final e = await _viaInteractivo(const FormatException('bad'));
      expect(e.error, isNot(isA<ExcepcionRed>()));
      expect(clasificarErrorMe(e), ErrorMe.otro);
    });

    test('unknown + HandshakeException → crudo → ErrorMe.otro', () async {
      final e = await _viaInteractivo(const HandshakeException('tls'));
      expect(e.error, isNot(isA<ExcepcionRed>()));
      expect(clasificarErrorMe(e), ErrorMe.otro);
    });
  });

  group('integración dio 5.9.2: SocketException durante el ENVÍO', () {
    test('el adapter corta tras aceptar la conexión → unknown + response null → transporte',
        () async {
      final crudo = await _viaAdapterCrudo(
        const SocketException('Connection reset by peer'),
        data: {'campo': 'x'}, // POST con cuerpo: el adapter drena y recién corta
      );
      // [VERIFICADO] dio 5.9.2 entrega una SocketException NO-DioException como unknown/response null
      // (DioMixin.assureDioException → type por defecto). Si cambiara el tipo, este expect lo delata.
      expect(crudo.type, DioExceptionType.unknown);
      expect(crudo.response, isNull);
      expect(crudo.error, isA<SocketException>());
      expect(clasificarFallaDio(crudo), ClaseFallaDio.sinRespuestaTransporte);

      // Y el camino interactivo (con ErrorInterceptor) lo traduce a ExcepcionRed → fallback offline.
      final interactivo = await _viaInteractivo(
        const SocketException('Connection reset by peer'),
        data: {'campo': 'x'},
      );
      expect(interactivo.error, isA<ExcepcionRed>());
      expect(clasificarErrorMe(interactivo), ErrorMe.transporte);
    });
  });
}
