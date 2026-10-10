/// perfil_sesion_fallback_test.dart — CTT-138 commit 3.
///
/// PerfilSesion.build resuelve la sesión en un [ResultadoSesion]:
///   - /me OK                                   → online.
///   - /me transporte + perfil cacheado del uid
///     (Trabajador/Residente)                   → offline (perfil reconstruido).
///   - /me transporte + rol Coord/Admin, o sin
///     caché, o uid distinto                     → sinSesion.
///   - /me 401 / 403-code (ExcepcionCuentaRevocada) → revocada.
///   - usuario Firebase null                     → sinSesion + limpiar().
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

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

class _MockUser extends Mock implements fb.User {}

class _MockRepo extends Mock implements PerfilRepository {}

class _MockStorage extends Mock implements SecureStorageService {}

const _uid = 'firebase-uid-luis';

PerfilUsuario _perfil({
  required String id,
  RolUsuario rol = RolUsuario.trabajador,
}) =>
    PerfilUsuario(
      id: id,
      nombreCompleto: 'Luis Fuentes',
      email: 'luis@andessur.cl',
      esSuperAdmin: false,
      empresas: [
        EmpresaPerfil(
          empresaId: 'emp-1',
          empresaNombre: 'Andes Sur',
          rol: rol,
        ),
      ],
    );

DioException _transporte() => DioException(
      requestOptions: RequestOptions(path: '/me'),
      error: const ExcepcionRed('sin conexión'),
      type: DioExceptionType.connectionError,
    );

void main() {
  late BaseDatosCTT db;
  late UsuarioActivoDao dao;
  late _MockRepo repo;
  late _MockStorage storage;

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    dao = UsuarioActivoDao(db);
    repo = _MockRepo();
    storage = _MockStorage();
    // Token ya presente (no se re-guarda). guardar* del camino online son no-op.
    when(() => storage.obtenerToken()).thenAnswer((_) async => 'tok');
    when(() => storage.guardarToken(any())).thenAnswer((_) async {});
    when(() => storage.guardarEmpresaId(any())).thenAnswer((_) async {});
    when(() => storage.guardarUsuarioId(any())).thenAnswer((_) async {});
  });
  tearDown(() => db.close());

  fb.User _user(String uid) {
    final u = _MockUser();
    when(() => u.uid).thenReturn(uid);
    return u;
  }

  ProviderContainer _contenedor(fb.User? user) => ProviderContainer(overrides: [
        firebaseAuthStreamProvider.overrideWith((ref) => Stream.value(user)),
        perfilRepositoryProvider.overrideWithValue(repo),
        usuarioActivoDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
      ]);

  /// Siembra una fila cacheada para [_uid] con el rol dado.
  Future<void> sembrarCache(RolUsuario rol) => dao.guardarPerfil(
        perfil: _perfil(id: 'ctt-id', rol: rol),
        firebaseUid: _uid,
        empresaId: 'emp-1',
        empresaNombre: 'Andes Sur',
        rolActual: rol.valor,
      );

  test('online: /me OK → ResultadoSesion.online con el perfil del servidor', () async {
    when(() => repo.obtenerPerfil()).thenAnswer((_) async => _perfil(id: 'ctt-id'));
    final c = _contenedor(_user(_uid));
    addTearDown(c.dispose);

    final r = await c.read(perfilSesionProvider.future);
    expect(r.modo, ModoSesion.online);
    expect(r.perfil!.id, 'ctt-id');
  });

  test('transporte + Trabajador cacheado → offline (perfil reconstruido de Drift)',
      () async {
    await sembrarCache(RolUsuario.trabajador);
    when(() => repo.obtenerPerfil()).thenThrow(_transporte());
    final c = _contenedor(_user(_uid));
    addTearDown(c.dispose);

    final r = await c.read(perfilSesionProvider.future);
    expect(r.modo, ModoSesion.offline);
    expect(r.perfil!.empresas.single.empresaId, 'emp-1');
    expect(r.perfil!.empresas.single.rol, RolUsuario.trabajador);
  });

  test('transporte + Residente cacheado → offline', () async {
    await sembrarCache(RolUsuario.residente);
    when(() => repo.obtenerPerfil()).thenThrow(_transporte());
    final c = _contenedor(_user(_uid));
    addTearDown(c.dispose);

    expect((await c.read(perfilSesionProvider.future)).modo, ModoSesion.offline);
  });

  test('transporte + Coordinador cacheado → sinSesion (sin sesión offline)', () async {
    await sembrarCache(RolUsuario.coordinador);
    when(() => repo.obtenerPerfil()).thenThrow(_transporte());
    final c = _contenedor(_user(_uid));
    addTearDown(c.dispose);

    expect((await c.read(perfilSesionProvider.future)).modo, ModoSesion.sinSesion);
  });

  test('transporte + sin caché → sinSesion', () async {
    when(() => repo.obtenerPerfil()).thenThrow(_transporte());
    final c = _contenedor(_user(_uid));
    addTearDown(c.dispose);

    expect((await c.read(perfilSesionProvider.future)).modo, ModoSesion.sinSesion);
  });

  test('transporte + caché de OTRO uid → sinSesion', () async {
    await sembrarCache(RolUsuario.trabajador); // uid = _uid
    when(() => repo.obtenerPerfil()).thenThrow(_transporte());
    final c = _contenedor(_user('otro-uid'));
    addTearDown(c.dispose);

    expect((await c.read(perfilSesionProvider.future)).modo, ModoSesion.sinSesion);
  });

  test('403 con code de cuenta (ExcepcionCuentaRevocada) → revocada', () async {
    await sembrarCache(RolUsuario.trabajador);
    when(() => repo.obtenerPerfil()).thenThrow(DioException(
      requestOptions: RequestOptions(path: '/me'),
      error: const ExcepcionCuentaRevocada('usuario_deshabilitado'),
      type: DioExceptionType.badResponse,
    ));
    final c = _contenedor(_user(_uid));
    addTearDown(c.dispose);

    expect((await c.read(perfilSesionProvider.future)).modo, ModoSesion.revocada);
  });

  test('usuario Firebase null → sinSesion y limpia usuario_activo', () async {
    await sembrarCache(RolUsuario.trabajador);
    expect(await dao.obtenerActivo(), isNotNull);
    final c = _contenedor(null);
    addTearDown(c.dispose);

    expect((await c.read(perfilSesionProvider.future)).modo, ModoSesion.sinSesion);
    expect(await dao.obtenerActivo(), isNull); // limpiar() corrió
  });
}
