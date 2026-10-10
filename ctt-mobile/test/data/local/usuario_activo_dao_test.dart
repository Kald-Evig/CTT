/// usuario_activo_dao_test.dart — CTT-138 commit 1.
///
/// `guardarPerfil` debe persistir en `firebase_uid` el UID de Firebase
/// (`usuario.uid`), NO el id interno de CTT (`perfil.id`): el fallback offline
/// (CTT-138) casa la fila contra el uid que emite `authStateChanges()`.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/data/local/daos/usuario_activo_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

void main() {
  late BaseDatosCTT db;
  late UsuarioActivoDao dao;

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    dao = UsuarioActivoDao(db);
  });
  tearDown(() => db.close());

  PerfilUsuario perfilDe({required String id, bool superAdmin = false}) =>
      PerfilUsuario(
        id: id,
        nombreCompleto: 'Luis Fuentes',
        email: 'luis@andessur.cl',
        esSuperAdmin: superAdmin,
        empresas: const [
          EmpresaPerfil(
            empresaId: 'emp-1',
            empresaNombre: 'Andes Sur',
            rol: RolUsuario.trabajador,
          ),
        ],
      );

  test('guardarPerfil persiste el uid de Firebase en firebase_uid, no el id de CTT',
      () async {
    final perfil = perfilDe(id: '43c8297a-ctt-id');
    await dao.guardarPerfil(
      perfil: perfil,
      firebaseUid: 'pCcukEA7-firebase-uid',
      empresaId: 'emp-1',
      empresaNombre: 'Andes Sur',
      rolActual: 'trabajador',
    );

    final fila = await dao.obtenerActivo();
    expect(fila, isNotNull);
    expect(fila!.firebaseUid, 'pCcukEA7-firebase-uid'); // uid de Firebase
    expect(fila.firebaseUid, isNot(perfil.id)); // NO el id interno de CTT
    expect(fila.id, perfil.id); // el id interno sí es perfil.id
  });

  test('super_admin también guarda el uid de Firebase real (no cadena vacía)',
      () async {
    await dao.guardarPerfil(
      perfil: perfilDe(id: 'super-ctt-id', superAdmin: true),
      firebaseUid: 'super-firebase-uid',
      empresaId: '',
      empresaNombre: '',
      rolActual: '',
    );

    final fila = await dao.obtenerActivo();
    expect(fila!.firebaseUid, 'super-firebase-uid');
    expect(fila.esSuperAdmin, isTrue);
  });

  test('actualizarEmpresaActiva cambia empresa/nombre/rol sin tocar el resto (CTT-138)',
      () async {
    await dao.guardarPerfil(
      perfil: perfilDe(id: 'ctt-id'),
      firebaseUid: 'fb-uid',
      empresaId: 'emp-1',
      empresaNombre: 'Andes Sur',
      rolActual: 'trabajador',
    );

    await dao.actualizarEmpresaActiva(
      empresaId: 'emp-2',
      empresaNombre: 'Obras Biobío',
      rolActual: 'residente',
    );

    final fila = await dao.obtenerActivo();
    expect(fila!.empresaId, 'emp-2');
    expect(fila.empresaNombre, 'Obras Biobío');
    expect(fila.rolActual, 'residente');
    // El resto de la identidad no cambia.
    expect(fila.id, 'ctt-id');
    expect(fila.firebaseUid, 'fb-uid');
    expect(fila.email, 'luis@andessur.cl');
  });
}
