/// crear_dio_sync_test.dart — CTT-138 commit 7.
///
/// crearDioSync es la config ÚNICA del Dio de sync (foreground y headless). Un 2xx a
/// través de él —como el de una corrida de sync en background— renueva
/// ultimo_contacto_servidor vía UltimoContactoInterceptor, y trae X-Sync-Origen.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';

class _MockStorage extends Mock implements SecureStorageService {}

/// Adapter que responde 200 sin tocar la red (local al test).
class _Adapter200 implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        '{}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() => registerFallbackValue(DateTime(2000)));

  test('crearDioSync: un 2xx (como el del Dio headless) escribe ultimo_contacto',
      () async {
    final storage = _MockStorage();
    when(() => storage.guardarUltimoContacto(any())).thenAnswer((_) async {});

    final dio = crearDioSync(storage, Logger(level: Level.off))
      ..httpClientAdapter = _Adapter200();

    await dio.get<void>('/items/mis-items');

    verify(() => storage.guardarUltimoContacto(any())).called(1);
    // X-Sync-Origen lo setea crearDioSync (compartido con dioSync).
    expect(dio.options.headers['X-Sync-Origen'], 'cola');
  });
}
