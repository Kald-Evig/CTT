/// perfil_sesion_defensa_carrera_test.dart — CTT-147 (corrección de revisión).
///
/// La fase 1 de la defensa SOLO debe evaluarse en la PRIMERA resolución de la sesión en este
/// proceso. Reproduce la carrera del logout: `cerrarSesion` hace
/// `Future.wait([signOut(), limpiarSesion()])`; signOut emite null por authStateChanges ANTES
/// de que deleteAll termine, así que PerfilSesion.build ve `usuario == null` con el token todavía
/// presente. Sin la guarda, eso dispara la defensa (requiereSanar + marca "sanar") en un logout
/// normal — un falso positivo.
///
/// Este test FALLA en af9a135 (sin la guarda: la 2ª emisión null da requiereSanar y escribe la
/// marca) y PASA con la corrección (da sinSesion y no escribe la marca). path_provider se mockea
/// a un directorio temporal para que la defensa sea FUNCIONAL en el test (si no,
/// crearDefensaSesionIo lanzaría y la defensa quedaría neutralizada, ocultando el bug).
///
// ignore_for_file: depend_on_referenced_packages — estos paquetes (platform interfaces de
// path_provider) solo se usan acá para mockear el sistema de archivos en el test.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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

/// path_provider fake: devuelve dirs temporales para soporte y documentos.
class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.soporte, this.docs);
  final String soporte;
  final String docs;
  @override
  Future<String?> getApplicationSupportPath() async => soporte;
  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
}

PerfilUsuario _perfil() => const PerfilUsuario(
      id: 'ctt-id',
      nombreCompleto: 'Luis Fuentes',
      email: 'luis@andessur.cl',
      esSuperAdmin: false,
      empresas: [
        EmpresaPerfil(
          empresaId: 'emp-1',
          empresaNombre: 'Andes Sur',
          rol: RolUsuario.trabajador,
        ),
      ],
    );

void main() {
  late Directory tmp;
  late File marcaSanar;
  late BaseDatosCTT db;
  late _MockRepo repo;
  late _MockStorage storage;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ctt_defensa_carrera');
    final soporte = Directory(p.join(tmp.path, 'support'))..createSync();
    final docs = Directory(p.join(tmp.path, 'app_flutter'))..createSync();
    PathProviderPlatform.instance = _FakePathProvider(soporte.path, docs.path);
    marcaSanar = File(p.join(soporte.path, 'ctt_defensa_sanar'));

    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    repo = _MockRepo();
    storage = _MockStorage();
    when(() => storage.obtenerToken()).thenAnswer((_) async => 'tok'); // token presente
    when(() => storage.guardarToken(any())).thenAnswer((_) async {});
    when(() => storage.guardarEmpresaId(any())).thenAnswer((_) async {});
    when(() => storage.guardarUsuarioId(any())).thenAnswer((_) async {});
    when(() => storage.eliminarToken()).thenAnswer((_) async {});
    when(() => repo.obtenerPerfil()).thenAnswer((_) async => _perfil());
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  fb.User usuarioFake() {
    final u = _MockUser();
    when(() => u.uid).thenReturn('firebase-uid-luis');
    return u;
  }

  test(
      'carrera del logout: usuario → null con token presente → sinSesion, '
      'NO requiereSanar y NO escribe la marca de sanar', () async {
    final ctrl = StreamController<fb.User?>();
    addTearDown(ctrl.close);

    final c = ProviderContainer(
      overrides: [
        firebaseAuthStreamProvider.overrideWith((ref) => ctrl.stream),
        perfilRepositoryProvider.overrideWithValue(repo),
        usuarioActivoDaoProvider.overrideWithValue(UsuarioActivoDao(db)),
        secureStorageProvider.overrideWithValue(storage),
        baseDatosCTTProvider.overrideWithValue(db),
      ],
    );
    addTearDown(c.dispose);

    final modos = <ModoSesion>[];
    final sub = c.listen(
      perfilSesionProvider,
      (_, next) {
        final v = next.valueOrNull;
        if (v != null) modos.add(v.modo);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    // 1ª resolución: hay usuario → online (se "consume" la primera resolución del proceso).
    ctrl.add(usuarioFake());
    await pumpEventQueue(times: 50);

    // 2ª resolución: logout emite null con el token todavía presente (la carrera).
    ctrl.add(null);
    await pumpEventQueue(times: 50);

    expect(modos.first, ModoSesion.online, reason: 'la 1ª emisión debe resolver online');
    expect(
      modos.last,
      ModoSesion.sinSesion,
      reason: 'un logout normal NO debe activar la defensa (esto falla en af9a135)',
    );
    expect(modos, isNot(contains(ModoSesion.requiereSanar)));
    expect(
      marcaSanar.existsSync(),
      isFalse,
      reason: 'no debe escribirse la marca de sanar en un logout normal',
    );
  });
}
