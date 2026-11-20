/// revalidador_cableado_test.dart — CTT-157. Tests del CABLEADO del revalidador: que cada
/// disparador llega de verdad a la señal/controlador (los tests de G2 manejaban `solicitar()`
/// directo y NO ejercitaban el cableado). Cada Wi se rompe a propósito para verlo en rojo.
///   W1 interceptor → callback 2xx (y null seguro para el headless).
///   W2 dioClient (interactivo) 2xx → bombea indicioConexion.
///   W3 dioSync (cola foreground) 2xx → bombea indicioConexion.
///   W4 ConectividadListener flanco offline→online → bombea indicioConexion.
///   W5 RevalidadorForeground: estadoAuth=offline → controlador.alCambiarEstadoOffline; ciclo de vida.
///   W6 RevalidadorForeground: indicioConexion → controlador.solicitar.
///
// ignore_for_file: depend_on_referenced_packages — los platform interfaces (connectivity_plus,
// plugin_platform_interface) solo se usan acá para fakear la conectividad en el test.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ctt_mobile/app.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/network/indicio_conexion.dart';
import 'package:ctt_mobile/core/network/interceptors/ultimo_contacto_interceptor.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync_ui.dart';
import 'package:ctt_mobile/core/sync/conectividad_listener.dart';
import 'package:ctt_mobile/core/sync/guarda_reconciliacion.dart';
import 'package:ctt_mobile/core/sync/revalidador_sesion.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/presentation/auth/revalidador_foreground.dart';

class _MockStorage extends Mock implements SecureStorageService {}

class _MockSyncDao extends Mock implements SyncDao {}

class _MockGuarda extends Mock implements GuardaReconciliacion {}

/// Adapter que responde 200 sin tocar la red (como en crear_dio_sync_test.dart).
class _Adapter200 implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
          Future<void>? cancelFuture,) async =>
      ResponseBody.fromString('{}', 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},);
  @override
  void close({bool force = false}) {}
}

class _FakeConnectivity extends ConnectivityPlatform with MockPlatformInterfaceMixin {
  final _ctrl = StreamController<List<ConnectivityResult>>.broadcast();
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _ctrl.stream;
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];
  void emitir(List<ConnectivityResult> r) => _ctrl.add(r);
}

/// Espía del controlador: registra lo que el CABLEADO le pide, sin efectos (ni timers ni
/// re-resolución), para que el test del widget quede acotado al cableado.
class _SpyRevalidador extends RevalidadorSesion {
  _SpyRevalidador() : super(reResolver: () async {});
  final offline = <bool>[];
  final ciclos = <AppLifecycleState>[];
  int solicitudes = 0;
  @override
  Future<void> solicitar() async => solicitudes++;
  @override
  void alCambiarEstadoOffline(bool o) => offline.add(o);
  @override
  void alCambiarCicloDeVida(AppLifecycleState s) => ciclos.add(s);
}

Response<dynamic> _resp(int code) =>
    Response<dynamic>(requestOptions: RequestOptions(path: '/x'), statusCode: code);

void main() {
  setUpAll(() => registerFallbackValue(DateTime(2000)));

  _MockStorage storageParaDio() {
    final s = _MockStorage();
    when(() => s.obtenerToken()).thenAnswer((_) async => 'tok');
    when(() => s.obtenerEmpresaId()).thenAnswer((_) async => null);
    when(() => s.guardarUltimoContacto(any())).thenAnswer((_) async {});
    return s;
  }

  // W1 — el interceptor llama al callback solo en 2xx; sin callback (headless) no lanza.
  test('W1: UltimoContactoInterceptor → alContacto2xx solo en 2xx; null es seguro', () {
    final s = _MockStorage();
    when(() => s.guardarUltimoContacto(any())).thenAnswer((_) async {});
    var n = 0;
    final i = UltimoContactoInterceptor(s, alContacto2xx: () => n++);
    i.onResponse(_resp(200), ResponseInterceptorHandler());
    expect(n, 1, reason: '2xx avisa');
    i.onResponse(_resp(304), ResponseInterceptorHandler());
    expect(n, 1, reason: 'no-2xx no avisa');
    // headless: sin callback, un 2xx no lanza.
    UltimoContactoInterceptor(s).onResponse(_resp(200), ResponseInterceptorHandler());
  });

  // W2 — un 2xx por el Dio interactivo bombea indicioConexion.
  test('W2: dioClient bombea indicioConexion ante un 2xx', () async {
    final c = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(storageParaDio())],);
    addTearDown(c.dispose);
    final dio = c.read(dioClientProvider)..httpClientAdapter = _Adapter200();
    final antes = c.read(indicioConexionProvider);
    await dio.get<void>('/x');
    await pumpEventQueue();
    expect(c.read(indicioConexionProvider), antes + 1);
  });

  // W3 — un 2xx por el Dio de la cola foreground bombea indicioConexion.
  test('W3: dioSync bombea indicioConexion ante un 2xx', () async {
    final c = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(storageParaDio())],);
    addTearDown(c.dispose);
    final dio = c.read(dioSyncProvider)..httpClientAdapter = _Adapter200();
    final antes = c.read(indicioConexionProvider);
    await dio.get<void>('/x');
    await pumpEventQueue();
    expect(c.read(indicioConexionProvider), antes + 1);
  });

  // W4 — el flanco offline→online de ConectividadListener bombea indicioConexion.
  test('W4: ConectividadListener bombea indicioConexion en el flanco offline→online', () async {
    final original = ConnectivityPlatform.instance;
    final fake = _FakeConnectivity();
    ConnectivityPlatform.instance = fake;
    addTearDown(() => ConnectivityPlatform.instance = original);

    final syncDao = _MockSyncDao();
    when(() => syncDao.liberarBackoffRed()).thenAnswer((_) async => 0);
    final guarda = _MockGuarda();
    when(() => guarda.reconciliarSiCorresponde()).thenAnswer((_) async {});

    final c = ProviderContainer(overrides: [
      syncDaoProvider.overrideWithValue(syncDao),
      cicloSyncUiProvider.overrideWithValue(CicloSyncUi(() async {})),
      guardaReconciliacionProvider.overrideWithValue(guarda),
    ],);
    addTearDown(c.dispose);
    c.read(conectividadListenerProvider); // activa la suscripción
    final antes = c.read(indicioConexionProvider);

    fake.emitir([ConnectivityResult.none]); // offline
    await pumpEventQueue();
    fake.emitir([ConnectivityResult.wifi]); // online → flanco
    await pumpEventQueue();

    expect(c.read(indicioConexionProvider), greaterThan(antes));
  });

  // W5 — el widget alimenta estadoAuth=offline y el ciclo de vida al controlador.
  testWidgets('W5: RevalidadorForeground → alCambiarEstadoOffline(true) y alCambiarCicloDeVida',
      (tester) async {
    final spy = _SpyRevalidador();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        revalidadorSesionProvider.overrideWithValue(spy),
        estadoAuthProvider.overrideWith((ref) => EstadoAuth.autenticadoOffline),
      ],
      child: const RevalidadorForeground(child: SizedBox()),
    ),);
    await tester.pump();
    expect(spy.offline, contains(true), reason: 'estadoAuth=offline → alCambiarEstadoOffline(true)');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(spy.ciclos, contains(AppLifecycleState.paused), reason: 'ciclo de vida → controlador');
  });

  // W6 — el widget alimenta el indicio de conexión al controlador (solicitar).
  testWidgets('W6: RevalidadorForeground → indicioConexion bombeado llama solicitar()',
      (tester) async {
    final spy = _SpyRevalidador();
    late ProviderContainer c;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        revalidadorSesionProvider.overrideWithValue(spy),
        estadoAuthProvider.overrideWith((ref) => EstadoAuth.autenticadoOffline),
      ],
      child: Builder(builder: (ctx) {
        c = ProviderScope.containerOf(ctx);
        return const RevalidadorForeground(child: SizedBox());
      },),
    ),);
    await tester.pump();
    final antes = spy.solicitudes;

    c.read(indicioConexionProvider.notifier).notificar(); // disparador 1/2
    await tester.pump();

    expect(spy.solicitudes, antes + 1, reason: 'el indicio bombeado llega a solicitar()');
  });
}
