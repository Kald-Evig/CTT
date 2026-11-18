/// empresa_activa_multiempresa_test.dart — CTT-164.
///
/// La empresa activa se resuelve y valida DENTRO de PerfilSesion.build() (camino online):
///   · N=1 → esa empresa.
///   · N>1 → leer `_ctt_empresa_id`; si está en perfil.empresas → esa; si no → borrarla y null.
/// `guardarPerfil` recibe la empresa RESUELTA (nunca '' cuando hay una válida). EmpresaActiva
/// lee esa empresa de forma síncrona desde perfilSesion. Offline sigue usando usuario_activo.
///
/// Camino REAL: contenedor real; se leen perfilSesionProvider y empresaActivaProvider de verdad
/// (no se sobrescriben con valores fijos). Solo se sobrescriben las dependencias externas
/// (firebaseAuthStream, PerfilRepository, UsuarioActivoDao, SecureStorage).
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/errors/exceptions.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/data/local/daos/usuario_activo_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/repositories/perfil_repository.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';
import 'package:ctt_mobile/presentation/auth/perfil_notifier.dart';
import 'package:ctt_mobile/presentation/empresa/empresa_activa_notifier.dart';

class _MockUser extends Mock implements fb.User {}

class _MockRepo extends Mock implements PerfilRepository {}

/// Fake con estado real de SecureStorage (map interno), para que la resolución lea lo que
/// `seleccionar()`/`guardarPerfil` escribieron. Solo se implementan los métodos que el camino
/// online usa; el resto lanza (Fake.noSuchMethod) si se invoca.
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
  // CTT-164: borrado selectivo de la empresa.
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
}

const _uid = 'fb-uid-luis';

EmpresaPerfil _emp(String id, {RolUsuario rol = RolUsuario.trabajador}) =>
    EmpresaPerfil(empresaId: id, empresaNombre: 'Empresa $id', rol: rol);

PerfilUsuario _perfil({
  String id = 'ctt-id',
  required List<EmpresaPerfil> empresas,
}) =>
    PerfilUsuario(
      id: id,
      nombreCompleto: 'Luis Fuentes',
      email: 'luis@andessur.cl',
      esSuperAdmin: false,
      empresas: empresas,
    );

fb.User _user(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

DioException _transporte() => DioException(
      requestOptions: RequestOptions(path: '/me'),
      error: const ExcepcionRed('sin conexión'),
      type: DioExceptionType.connectionError,
    );

/// Entorno real: contenedor con solo las dependencias externas sobrescritas.
({ProviderContainer c, _FakeStorage storage, UsuarioActivoDao dao, _MockRepo repo})
    _entorno({
  fb.User? user,
  Stream<fb.User?>? stream,
  BaseDatosCTT? db,
  _FakeStorage? storage,
}) {
  final base = db ?? BaseDatosCTT.conConexion(NativeDatabase.memory());
  final dao = UsuarioActivoDao(base);
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
    if (db == null) base.close();
  });
  return (c: c, storage: store, dao: dao, repo: repo);
}

/// Mantiene vivos (autoDispose) perfilSesion y empresaActiva durante los gaps async.
void _mantenerVivos(ProviderContainer c) {
  c.listen(perfilSesionProvider, (_, __) {});
  c.listen(empresaActivaProvider, (_, __) {});
}

/// true si el router iría a /seleccion-empresa (réplica de app.dart:140-141).
bool _necesitaSeleccion(ProviderContainer c) {
  final perfil = c.read(perfilSesionProvider).valueOrNull?.perfil;
  final empresaActiva = c.read(empresaActivaProvider);
  final multiEmpresa = (perfil?.empresas.length ?? 0) > 1;
  return multiEmpresa && empresaActiva == null;
}

void main() {
  // T1 — N>1, empresa elegida, rebuild de PerfilSesion → conserva la empresa y no va a selección.
  test('T1: N>1 + rebuild de PerfilSesion conserva la empresa (no /seleccion-empresa)',
      () async {
    final e = _entorno(user: _user(_uid));
    e.storage.m['empresa'] = 'emp-2'; // selección previa válida
    when(() => e.repo.obtenerPerfil())
        .thenAnswer((_) async => _perfil(empresas: [_emp('emp-1'), _emp('emp-2')]));
    _mantenerVivos(e.c);

    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();
    expect(e.c.read(empresaActivaProvider), 'emp-2',
        reason: 'arranque N>1 restaura la empresa persistida',);

    e.c.invalidate(perfilSesionProvider); // rebuild en caliente
    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    expect(e.c.read(empresaActivaProvider), 'emp-2', reason: 'el rebuild conserva la empresa');
    expect(_necesitaSeleccion(e.c), isFalse, reason: 'el router NO va a /seleccion-empresa');
  });

  // T2 — Arranque online en frío, N>1, _ctt_empresa_id válido → restaura sin pasar por selección.
  test('T2: arranque online N>1 con _ctt_empresa_id válido restaura sin selección', () async {
    final e = _entorno(user: _user(_uid));
    e.storage.m['empresa'] = 'emp-2';
    when(() => e.repo.obtenerPerfil())
        .thenAnswer((_) async => _perfil(empresas: [_emp('emp-1'), _emp('emp-2')]));
    _mantenerVivos(e.c);

    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    expect(e.c.read(empresaActivaProvider), 'emp-2');
    expect(_necesitaSeleccion(e.c), isFalse);
  });

  // T3 — _ctt_empresa_id que no está en perfil.empresas → null (selección) y la clave se borra.
  test('T3: _ctt_empresa_id ajeno a perfil.empresas → null y la clave queda borrada', () async {
    final e = _entorno(user: _user(_uid));
    e.storage.m['empresa'] = 'emp-AJENA'; // no está en el perfil
    when(() => e.repo.obtenerPerfil())
        .thenAnswer((_) async => _perfil(empresas: [_emp('emp-1'), _emp('emp-2')]));
    _mantenerVivos(e.c);

    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    expect(e.c.read(empresaActivaProvider), isNull, reason: 'empresa inválida → va a selección');
    expect(await e.storage.obtenerEmpresaId(), isNull,
        reason: 'la empresa inválida se borra de _ctt_empresa_id (assertion discriminante)',);
  });

  // T4 — online N>1 válido → usuario_activo.empresaId = esa empresa (no ''); luego transporte →
  // ResultadoSesion.offline con esa empresa (no sinSesion).
  test('T4: online N>1 persiste la empresa resuelta en usuario_activo; transporte → offline',
      () async {
    final db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    addTearDown(db.close);
    final storage = _FakeStorage()..m['empresa'] = 'emp-2';

    // Fase online.
    final e1 = _entorno(user: _user(_uid), db: db, storage: storage);
    when(() => e1.repo.obtenerPerfil())
        .thenAnswer((_) async => _perfil(empresas: [_emp('emp-1'), _emp('emp-2')]));
    _mantenerVivos(e1.c);
    await e1.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    final fila = await e1.dao.obtenerActivo();
    expect(fila?.empresaId, 'emp-2',
        reason: 'guardarPerfil escribe la empresa resuelta, no ""',);

    // Fase offline: nuevo proceso, /me falla por transporte, misma base y storage.
    final e2 = _entorno(user: _user(_uid), db: db, storage: storage);
    when(() => e2.repo.obtenerPerfil()).thenThrow(_transporte());
    _mantenerVivos(e2.c);

    final r = await e2.c.read(perfilSesionProvider.future);
    expect(r.modo, ModoSesion.offline,
        reason: 'con la empresa en usuario_activo, transporte → offline (no sinSesion)',);
    expect(r.perfil?.empresas.single.empresaId, 'emp-2');
  });

  // T5 — N=1 → comportamiento igual al actual (GUARDA de regresión: verde antes y después).
  test('T5: N=1 → auto-selección como hoy (regresión)', () async {
    final e = _entorno(user: _user(_uid));
    when(() => e.repo.obtenerPerfil())
        .thenAnswer((_) async => _perfil(empresas: [_emp('emp-unica')]));
    _mantenerVivos(e.c);

    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    expect(e.c.read(empresaActivaProvider), 'emp-unica');
    expect(await e.storage.obtenerEmpresaId(), 'emp-unica');
    expect((await e.dao.obtenerActivo())?.empresaId, 'emp-unica');
  });

  // T6 — Logout → el siguiente usuario no hereda la empresa (GUARDA de seguridad).
  test('T6: tras logout (limpieza), otro usuario multi no hereda la empresa', () async {
    final db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    addTearDown(db.close);
    final storage = _FakeStorage();

    // Usuario A: una empresa → persiste emp-1.
    final a = _entorno(user: _user('uid-A'), db: db, storage: storage);
    when(() => a.repo.obtenerPerfil())
        .thenAnswer((_) async => _perfil(id: 'A', empresas: [_emp('emp-1')]));
    _mantenerVivos(a.c);
    await a.c.read(perfilSesionProvider.future);
    await pumpEventQueue();
    expect(await storage.obtenerEmpresaId(), 'emp-1');
    a.c.dispose();

    // Logout: cerrarSesion hace deleteAll (SecureStorage) y el null-emission limpia usuario_activo.
    await storage.limpiarSesion();
    await a.dao.limpiar();

    // Usuario B: multi, su perfil incluye emp-1 (peor caso) → NO debe heredarla.
    final b = _entorno(user: _user('uid-B'), db: db, storage: storage);
    when(() => b.repo.obtenerPerfil())
        .thenAnswer((_) async => _perfil(id: 'B', empresas: [_emp('emp-1'), _emp('emp-9')]));
    _mantenerVivos(b.c);
    await b.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    expect(b.c.read(empresaActivaProvider), isNull,
        reason: 'B debe elegir empresa; no hereda emp-1 de A',);
  });

  // T7 — Carrera: seleccionar(B) en curso + rebuild de PerfilSesion que arrancó antes → final B.
  // El rebuild "arrancó antes" (invalidate previo) pero su /me se completa DESPUÉS de seleccionar,
  // que es el orden realista: build() espera la red (/me) mientras las 2 escrituras locales de
  // seleccionar ya terminaron. Determinista vía un Completer que controla /me.
  test('T7: carrera seleccionar(B) + rebuild previo → estado final B', () async {
    final e = _entorno(user: _user(_uid));
    // Sin empresa persistida → arranca en selección (empresaActiva null).
    final perfilMulti = _perfil(empresas: [_emp('emp-1'), _emp('emp-2')]);
    when(() => e.repo.obtenerPerfil()).thenAnswer((_) async => perfilMulti);
    _mantenerVivos(e.c);

    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();
    expect(e.c.read(empresaActivaProvider), isNull, reason: 'parte en selección');

    // El rebuild "arranca antes": su /me queda bloqueado en un Completer.
    final gate = Completer<PerfilUsuario>();
    when(() => e.repo.obtenerPerfil()).thenAnswer((_) => gate.future);
    e.c.invalidate(perfilSesionProvider);
    await pumpEventQueue(); // build llega al await de /me y se bloquea

    // Mientras el rebuild está en vuelo, el usuario elige B (persiste y setea state).
    await e.c.read(empresaActivaProvider.notifier).seleccionar(_emp('emp-2'));
    expect(e.c.read(empresaActivaProvider), 'emp-2');

    // Ahora /me del rebuild responde: lee _ctt_empresa_id = emp-2 (ya persistido) → resuelve emp-2.
    gate.complete(perfilMulti);
    await e.c.read(perfilSesionProvider.future);
    await pumpEventQueue();

    expect(e.c.read(empresaActivaProvider), 'emp-2',
        reason: 'el rebuild re-resuelve a B porque _ctt_empresa_id = B es la fuente de verdad',);
  });
}
