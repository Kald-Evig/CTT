/// ultimo_contacto_interceptor_test.dart — CTT-138 commit 4.
///
/// El interceptor guarda el último contacto SOLO ante 2xx.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/network/interceptors/ultimo_contacto_interceptor.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';

class _MockStorage extends Mock implements SecureStorageService {}

void main() {
  setUpAll(() => registerFallbackValue(DateTime(2000)));

  late _MockStorage storage;
  late UltimoContactoInterceptor interceptor;

  setUp(() {
    storage = _MockStorage();
    when(() => storage.guardarUltimoContacto(any())).thenAnswer((_) async {});
    interceptor = UltimoContactoInterceptor(storage);
  });

  Response<dynamic> _resp(int status) => Response<dynamic>(
        requestOptions: RequestOptions(path: '/me'),
        statusCode: status,
      );

  test('200 → guarda último contacto', () {
    interceptor.onResponse(_resp(200), ResponseInterceptorHandler());
    verify(() => storage.guardarUltimoContacto(any())).called(1);
  });

  test('204 → guarda último contacto', () {
    interceptor.onResponse(_resp(204), ResponseInterceptorHandler());
    verify(() => storage.guardarUltimoContacto(any())).called(1);
  });

  test('304 (no-2xx) → NO guarda', () {
    interceptor.onResponse(_resp(304), ResponseInterceptorHandler());
    verifyNever(() => storage.guardarUltimoContacto(any()));
  });
}
