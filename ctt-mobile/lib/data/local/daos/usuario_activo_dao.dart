/// usuario_activo_dao.dart — Acceso a la tabla usuario_activo en Drift.
///
/// Solo existe un registro a la vez: el perfil de la sesión activa.
/// Se escribe después del fetch de /me y se borra al hacer logout.
library;

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';

part 'usuario_activo_dao.g.dart';

@riverpod
UsuarioActivoDao usuarioActivoDao(UsuarioActivoDaoRef ref) =>
    UsuarioActivoDao(ref.watch(baseDatosCTTProvider));

@DriftAccessor(tables: [UsuarioActivoTable])
class UsuarioActivoDao extends DatabaseAccessor<BaseDatosCTT>
    with _$UsuarioActivoDaoMixin {
  UsuarioActivoDao(super.db);

  /// Guarda (o reemplaza) el perfil activo en la tabla.
  Future<void> guardarPerfil({
    required PerfilUsuario perfil,
    required String empresaId,
    required String empresaNombre,
    required String rolActual,
  }) async {
    await delete(usuarioActivoTable).go();
    await into(usuarioActivoTable).insert(
      UsuarioActivoTableCompanion.insert(
        id: perfil.id,
        firebaseUid: perfil.esSuperAdmin ? '' : perfil.id,
        nombreCompleto: perfil.nombreCompleto,
        email: perfil.email,
        rolActual: rolActual,
        empresaId: empresaId,
        empresaNombre: empresaNombre,
        esSuperAdmin: Value(perfil.esSuperAdmin),
      ),
    );
  }

  Future<UsuarioActivoTableData?> obtenerActivo() =>
      (select(usuarioActivoTable)..limit(1)).getSingleOrNull();

  Future<void> limpiar() => delete(usuarioActivoTable).go();
}
