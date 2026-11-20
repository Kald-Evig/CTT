/// revalidador_integracion_test.dart — CTT-157. Camino REAL: contenedor real con PerfilSesion,
/// estadoAuth y estadoVentanaOffline SIN sobrescribir; /me y el estado offline falsos. Se maneja
/// el revalidador por su provider (revalidadorSesionProvider) y se observan los providers reales.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/app.dart';
import 'package:ctt_mobile/core/errors/exceptions.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/data/local/daos/usuario_activo_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/repositories/perfil_repository.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';
import 'package:ctt_mobile/presentation/empresa/empresa_activa_notifier.dart';
import 'package:ctt_mobile/presentation/auth/perfil_notifier.dart';
import 'package:ctt_mobile/presentation/auth/revalidador_foreground.dart';
import 'package:ctt_mobile/presentation/auth/ventana_offline.dart';

class _MockUser extends Mock implements fb.User {}

class _MockRepo extends Mock implements PerfilRepository {}

class _FakeStorage extends Fake implements SecureStorageService {
  final Map<String, String?> m = {};
  @override
  Future<String?> obtenerToken() async => m['jwt'] ?? 'tok';
  @override
  Future<void> guardarToken(String v) async => m['jwt'] = v;
  @override
  Future<String?> obtenerEmpresaId() async => m['empresa'];
  @override
  Future<void> guardarEmpresaId(String v) async => m['empresa'] = v;
  @override
  Future<void> eliminarEmpresaId() async => m.remove('empresa');
  @override
  Future<void> guardarUsuarioId(String v) async => m['usuario'] = v;
  @override
  Future<String?> obtenerUsuarioId() async => m['usuario'];
  @override
  Future<void> guardarFirebaseUid(String v) async => m['fbuid'] = v;
  @override
  Future<void> limpiarSesion() async => m.clear();
  @override
  Future<DateTime?> obtenerUltimoContacto() async =>
      DateTime.now().toUtc().subtract(const Duration(minutes: 5));
}

const _uid = 'fb-uid-benja';

fb.User _user(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

EmpresaPerfil _emp(String id) =>
    EmpresaPerfil(empresaId: id, empresaNombre: 'Empresa $id', rol: RolUsuario.trabajador);

PerfilUsuario _perfil({
  List<EmpresaPerfil>? empresas,
  RolUsuario rol = RolUsuario.trabajador,
}) =>
    PerfilUsuario(
      id: 'ctt-id',
      nombreCompleto: 'Benjamín',
      email: 'benja@rionorte.cl',
      esSuperAdmin: false,
      empresas: empresas ?? [EmpresaPerfil(empresaId: 'emp-1', empresaNombre: 'E1', rol: rol)],
    );

DioException _transporte() => DioException(
      requestOptions: RequestOptions(path: '/me'),
      error: const ExcepcionRed('sin conexión'),
      type: DioExceptionType.connectionError,
    );

({ProviderContainer c, _FakeStorage storage, UsuarioActivoDao dao, _MockRepo repo}) _entorno({
  fb.User? user,
  Stream<fb.User?>? stream,
  _FakeStorage? storage,
}) {
  final db = BaseDatosCTT.conConexion(NativeDatabase.memory());
  final dao = UsuarioActivoDao(db);
  final repo = _MockRepo();
  final store = storage ?? _FakeStorage();
  final c = ProviderContainer(overrides: [
    firebaseAuthStreamProvider.overrideWith((ref) => stream ?? Stream.value(user)),
    perfilRepositoryProvider.overrideWithValue(repo),
    usuarioActivoDaoProvider.overrideWithValue(dao),
    secureStorageProvider.overrideWithValue(store),
  ],);
  addTearDown(() {
    c.dispose();
    db.close();
  });
  return (c: c, storage: store, dao: dao, repo: repo);
}

void _vivos(ProviderContainer c) {
  c.listen(perfilSesionProvider, (_, __) {});
  c.listen(estadoAuthProvider, (_, __) {});
  c.listen(estadoVentanaOfflineProvider, (_, __) {});
}

/// Siembra usuario_activo para que el fallback offline tenga de qué reconstruir.
Future<void> _sembrarOffline(UsuarioActivoDao dao, {required String empresaId}) =>
    dao.guardarPerfil(
      perfil: _perfil(empresas: [_emp(empresaId)]),
      firebaseUid: _uid,
      empresaId: empresaId,
      empresaNombre: 'E $empresaId',
      rolActual: 'trabajador',
    );

void main() {
  // T1 — Offline → dispara → /me 200 → autenticado + banner oculto.
  test('T1: offline → solicitar → /me 200 → estadoAuth=autenticado, esOffline=false', () async {
    final e = _entorno(user: _user(_uid));
    await _sembrarOffline(e.dao, empresaId: 'emp-1');
    when(() => e.repo.obtenerPerfil()).thenAnswer((_) async => throw _transporte());
    _vivos(e.c);

    expect((await e.c.read(perfilSesionProvider.future)).modo, ModoSesion.offline);
    expect(e.c.read(estadoAuthProvider), EstadoAuth.autenticadoOffline);

    final rev = e.c.read(revalidadorSesionProvider);
    rev.alCambiarEstadoOffline(true);
    when(() => e.repo.obtenerPerfil()).thenAnswer((_) async => _perfil());

    await rev.solicitar();
    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    expect(e.c.read(estadoAuthProvider), EstadoAuth.autenticado);
    expect((await e.c.read(estadoVentanaOfflineProvider.future)).esOffline, isFalse);
  });

  // T2 — Offline → dispara → /me transporte → sigue offline (pero SÍ llamó a /me).
  test('T2: offline → solicitar → /me transporte → sigue offline, /me se llamó', () async {
    final e = _entorno(user: _user(_uid));
    await _sembrarOffline(e.dao, empresaId: 'emp-1');
    var meCount = 0;
    when(() => e.repo.obtenerPerfil()).thenAnswer((_) async {
      meCount++;
      throw _transporte();
    });
    _vivos(e.c);
    await e.c.read(perfilSesionProvider.future);
    final antes = meCount;

    final rev = e.c.read(revalidadorSesionProvider);
    rev.alCambiarEstadoOffline(true);
    await rev.solicitar();
    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    expect(meCount, antes + 1, reason: 'la re-resolución llamó a /me una vez');
    expect(e.c.read(estadoAuthProvider), EstadoAuth.autenticadoOffline,
        reason: 'con transporte vuelve a offline, sin navegar',);
  });

  // T3 — Online (coordinador y trabajador): ningún disparador llama a /me. GUARDA.
  test('T3 (guarda): online → solicitar no llama a /me', () async {
    for (final rol in [RolUsuario.coordinador, RolUsuario.trabajador]) {
      final e = _entorno(user: _user(_uid));
      var meCount = 0;
      when(() => e.repo.obtenerPerfil()).thenAnswer((_) async {
        meCount++;
        return _perfil(rol: rol);
      });
      _vivos(e.c);
      await e.c.read(perfilSesionProvider.future);
      expect(e.c.read(estadoAuthProvider), EstadoAuth.autenticado);
      final antes = meCount;

      final rev = e.c.read(revalidadorSesionProvider);
      rev.alCambiarEstadoOffline(false); // online
      await rev.solicitar();
      await pumpEventQueue();
      expect(meCount, antes, reason: 'online ($rol): ningún /me');
    }
  });

  // T6 — Sin flash: durante la re-resolución estadoAuth NO pasa por cargando; termina autenticado.
  test('T6: re-resolución sin flash a /cargando (refresh, no reload)', () async {
    final e = _entorno(user: _user(_uid));
    await _sembrarOffline(e.dao, empresaId: 'emp-1');
    when(() => e.repo.obtenerPerfil()).thenAnswer((_) async => throw _transporte());
    final emisiones = <EstadoAuth>[];
    e.c.listen(perfilSesionProvider, (_, __) {});
    e.c.listen(estadoAuthProvider, (_, next) => emisiones.add(next), fireImmediately: true);
    e.c.listen(estadoVentanaOfflineProvider, (_, __) {});

    await e.c.read(perfilSesionProvider.future);
    emisiones.clear();

    final rev = e.c.read(revalidadorSesionProvider);
    rev.alCambiarEstadoOffline(true);
    when(() => e.repo.obtenerPerfil()).thenAnswer((_) async => _perfil());
    await rev.solicitar();
    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    expect(emisiones, contains(EstadoAuth.autenticado), reason: 'la sesión se re-resolvió');
    expect(emisiones, isNot(contains(EstadoAuth.cargando)),
        reason: 'invalidate = refresh: no hay flash a /cargando',);
  });

  // T7 — Carrera: logout durante una re-resolución en vuelo → NO hay guardarPerfil después de limpiar.
  test('T7: logout durante /me en vuelo → no re-escribe usuario_activo', () async {
    final ctrl = StreamController<fb.User?>();
    addTearDown(ctrl.close);
    final e = _entorno(stream: ctrl.stream);
    final gate = Completer<PerfilUsuario>();
    when(() => e.repo.obtenerPerfil()).thenAnswer((_) => gate.future);
    _vivos(e.c);

    ctrl.add(_user(_uid)); // 1ª resolución: build arranca y se bloquea en /me
    await pumpEventQueue(times: 30);

    ctrl.add(null); // logout en vuelo → rebuild con usuario null → dao.limpiar → sinSesion
    await pumpEventQueue(times: 30);

    gate.complete(_perfil()); // la /me del build viejo responde ahora
    await pumpEventQueue(times: 30);

    expect(await e.dao.obtenerActivo(), isNull,
        reason: 'el build viejo no debe re-escribir usuario_activo tras el logout',);
  });

  // T8 — Multi-empresa (CTT-164): offline en B → online con N>1 → empresa sigue B, sin selección.
  test('T8: offline en empresa B → online N>1 → empresaActiva sigue B', () async {
    final e = _entorno(user: _user(_uid));
    e.storage.m['empresa'] = 'emp-B';
    await _sembrarOffline(e.dao, empresaId: 'emp-B');
    when(() => e.repo.obtenerPerfil()).thenAnswer((_) async => throw _transporte());
    _vivos(e.c);
    await e.c.read(perfilSesionProvider.future);
    expect(e.c.read(estadoAuthProvider), EstadoAuth.autenticadoOffline);
    expect(e.c.read(empresaActivaProvider), 'emp-B');

    final rev = e.c.read(revalidadorSesionProvider);
    rev.alCambiarEstadoOffline(true);
    when(() => e.repo.obtenerPerfil())
        .thenAnswer((_) async => _perfil(empresas: [_emp('emp-A'), _emp('emp-B')]));
    await rev.solicitar();
    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    expect(e.c.read(estadoAuthProvider), EstadoAuth.autenticado);
    expect(e.c.read(empresaActivaProvider), 'emp-B', reason: 'conserva la empresa, no va a selección');
    final perfil = e.c.read(perfilSesionProvider).valueOrNull?.perfil;
    final multi = (perfil?.empresas.length ?? 0) > 1;
    expect(multi && e.c.read(empresaActivaProvider) == null, isFalse,
        reason: 'no necesita /seleccion-empresa',);
  });

  // T9 — Invariante (CTT-164): con la sesión online, ningún disparador re-resuelve PerfilSesion. GUARDA.
  test('T9 (guarda): online → solicitar repetido no re-resuelve PerfilSesion', () async {
    final e = _entorno(user: _user(_uid));
    var meCount = 0;
    when(() => e.repo.obtenerPerfil()).thenAnswer((_) async {
      meCount++;
      return _perfil(empresas: [_emp('emp-A'), _emp('emp-B')]);
    });
    e.storage.m['empresa'] = 'emp-A';
    _vivos(e.c);
    await e.c.read(perfilSesionProvider.future);
    final antes = meCount;

    final rev = e.c.read(revalidadorSesionProvider);
    rev.alCambiarEstadoOffline(false);
    await rev.solicitar();
    await rev.solicitar();
    await pumpEventQueue();
    expect(meCount, antes, reason: 'online: la pantalla de selección/race queda inalcanzable');
  });
}
