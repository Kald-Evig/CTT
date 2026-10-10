/// perfil_notifier.dart — Estado del perfil del usuario autenticado (CTT-138).
///
/// Observa el stream de Firebase Auth y carga /me al login. El resultado es un
/// [ResultadoSesion] que distingue online / offline / sesión revocada / sin sesión:
///   - /me OK                          → online (perfil del servidor, cacheado en Drift).
///   - /me falla por TRANSPORTE y hay
///     perfil cacheado del mismo uid    → offline (perfil reconstruido desde Drift),
///     SOLO para Trabajador/Residente.   Coordinador/Admin/super → sin sesión (requiere
///                                       conexión).
///   - /me 401 o 403 con code de cuenta → revocada → login.
///   - usuario Firebase == null         → sin sesión (logout real): se limpia el perfil.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/local/daos/usuario_activo_dao.dart';
import 'package:ctt_mobile/data/repositories/perfil_repository.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';
import 'package:ctt_mobile/presentation/auth/clasificador_auth_me.dart';

part 'perfil_notifier.g.dart';

/// Modo en que se resolvió la sesión al arrancar.
enum ModoSesion { online, offline, revocada, sinSesion }

/// Resultado de resolver la sesión: el modo + el perfil (presente en online/offline).
class ResultadoSesion {
  const ResultadoSesion.online(PerfilUsuario this.perfil) : modo = ModoSesion.online;
  const ResultadoSesion.offline(PerfilUsuario this.perfil)
      : modo = ModoSesion.offline;
  const ResultadoSesion.revocada()
      : modo = ModoSesion.revocada,
        perfil = null;
  const ResultadoSesion.sinSesion()
      : modo = ModoSesion.sinSesion,
        perfil = null;

  final ModoSesion modo;
  final PerfilUsuario? perfil;
}

/// Roles con sesión offline (decisión de Kald, CTT-138): solo Trabajador y Residente.
bool _rolConSesionOffline(String rol) =>
    rol == RolUsuario.trabajador.valor || rol == RolUsuario.residente.valor;

@riverpod
class PerfilSesion extends _$PerfilSesion {
  @override
  Future<ResultadoSesion> build() async {
    final usuario = await ref.watch(firebaseAuthStreamProvider.future);
    final dao = ref.read(usuarioActivoDaoProvider);
    if (usuario == null) {
      // Logout real: Firebase ya no tiene usuario. Se limpia el perfil local.
      await dao.limpiar();
      return const ResultadoSesion.sinSesion();
    }

    final storage = ref.read(secureStorageProvider);
    // Race condition: Firebase dispara authStateChanges() antes de que
    // iniciarSesion() complete el await de guardarToken(). Garantizamos el
    // token aquí antes de cualquier request a /me.
    if (await storage.obtenerToken() == null) {
      await storage.guardarToken(usuario.uid);
    }

    final repo = ref.read(perfilRepositoryProvider);
    final PerfilUsuario perfil;
    try {
      perfil = await repo.obtenerPerfil();
    } catch (e) {
      // NO se llama a limpiar() ante un error de /me: eso borraría el perfil del
      // que depende el fallback offline (ese era el defecto original de CTT-138).
      return _resolverErrorMe(e, usuario.uid, dao);
    }

    // Persistir empresa en SecureStorage solo cuando hay una sola. Con múltiples,
    // el usuario elige en SeleccionEmpresaScreen y EmpresaActiva guarda la elección.
    final empresa = perfil.empresas.length == 1 ? perfil.empresas.first : null;
    if (empresa != null) {
      await storage.guardarEmpresaId(empresa.empresaId);
    }
    await storage.guardarUsuarioId(perfil.id);

    // Persistir sesión en Drift para acceso offline. firebaseUid = usuario.uid
    // (Firebase), para que el fallback offline case contra el uid de authStateChanges.
    await dao.guardarPerfil(
      perfil: perfil,
      firebaseUid: usuario.uid,
      empresaId: empresa?.empresaId ?? '',
      empresaNombre: empresa?.empresaNombre ?? '',
      rolActual: empresa?.rol.valor ?? '',
    );

    return ResultadoSesion.online(perfil);
  }

  /// Decide qué hacer cuando /me falla, según el clasificador (CTT-138).
  Future<ResultadoSesion> _resolverErrorMe(
    Object error,
    String firebaseUid,
    UsuarioActivoDao dao,
  ) async {
    switch (clasificarErrorMe(error)) {
      case ErrorMe.revocada:
        return const ResultadoSesion.revocada();
      case ErrorMe.otro:
        // 403 de permiso u otro error no transitorio: no hay sesión offline válida.
        return const ResultadoSesion.sinSesion();
      case ErrorMe.transporte:
        final fila = await dao.obtenerActivo();
        // Necesita un perfil cacheado del MISMO uid de Firebase, con empresa activa.
        if (fila == null ||
            fila.firebaseUid != firebaseUid ||
            fila.empresaId.isEmpty) {
          return const ResultadoSesion.sinSesion();
        }
        // Solo Trabajador/Residente operan offline; Coordinador/Admin → login.
        if (!_rolConSesionOffline(fila.rolActual)) {
          return const ResultadoSesion.sinSesion();
        }
        return ResultadoSesion.offline(_perfilDesdeFila(fila));
    }
  }

  /// Reconstruye el [PerfilUsuario] desde la fila cacheada, con su única empresa
  /// activa (offline solo restaura esa empresa — decisión de Kald).
  PerfilUsuario _perfilDesdeFila(UsuarioActivoTableData fila) => PerfilUsuario(
        id: fila.id,
        nombreCompleto: fila.nombreCompleto,
        email: fila.email,
        esSuperAdmin: fila.esSuperAdmin,
        empresas: [
          EmpresaPerfil(
            empresaId: fila.empresaId,
            empresaNombre: fila.empresaNombre,
            rol: RolUsuario.fromString(fila.rolActual),
          ),
        ],
      );
}
