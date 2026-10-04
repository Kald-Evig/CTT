/// dio_sync_test.dart — CTT-103 D4: Dio de sync separado del interactivo.
///
/// El Dio de sync lleva X-Sync-Origen: cola y NO tiene ErrorInterceptor (el único que
/// dispara alCerrarSesion ante 401) → un 401 no puede desloguear desde el sync. El Dio
/// interactivo no lleva el header y conserva su ErrorInterceptor (401→logout).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/network/interceptors/error_interceptor.dart';

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('dioSync lleva X-Sync-Origen: cola y NO tiene ErrorInterceptor '
      '(un 401 no llama alCerrarSesion)', () {
    final sync = container.read(dioSyncProvider);
    expect(sync.options.headers['X-Sync-Origen'], 'cola');
    // ErrorInterceptor es el ÚNICO que cablea alCerrarSesion; sin él, el 401 del sync
    // no puede desloguear (lo pausa el ciclo).
    expect(sync.interceptors.whereType<ErrorInterceptor>(), isEmpty);
  });

  test('dioClient NO lleva X-Sync-Origen y conserva su ErrorInterceptor (401→logout)',
      () {
    final interactivo = container.read(dioClientProvider);
    expect(interactivo.options.headers.containsKey('X-Sync-Origen'), isFalse);
    expect(interactivo.interceptors.whereType<ErrorInterceptor>(), isNotEmpty);
  });
}
