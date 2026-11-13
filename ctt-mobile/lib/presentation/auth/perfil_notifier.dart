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

import 'dart:io' show Platform;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/security/defensa_sesion_io.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/daos/usuario_activo_dao.dart';
import 'package:ctt_mobile/data/repositories/perfil_repository.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';
import 'package:ctt_mobile/presentation/auth/clasificador_auth_me.dart';

part 'perfil_notifier.g.dart';

/// Modo en que se resolvió la sesión al arrancar. `requiereSanar` (CTT-147): se detectó el
/// estado roto de Firebase Auth y la app debe cerrarse para sanar en el próximo arranque.
enum ModoSesion { online, offline, revocada, sinSesion, requiereSanar }

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
  const ResultadoSesion.requiereSanar()
      : modo = ModoSesion.requiereSanar,
        perfil = null;

  final ModoSesion modo;
  final PerfilUsuario? perfil;
}

/// Roles con sesión offline (decisión de Kald, CTT-138): solo Trabajador y Residente.
bool _rolConSesionOffline(String rol) =>
    rol == RolUsuario.trabajador.valor || rol == RolUsuario.residente.valor;

/// Bandera EN MEMORIA (CTT-147): ¿ya se resolvió la sesión al menos una vez en ESTE proceso?
/// La fase 1 de la defensa solo se evalúa en la primera resolución (ver [DefensaSesion]).
class ResolucionSesionProceso {
  bool yaResolvio = false;
}

/// keepAlive: la bandera vive toda la vida del proceso y NO se reinicia con los rebuilds de
/// [PerfilSesion]. Ni `ref.invalidate(perfilSesionProvider)`, ni una nueva emisión de
/// `firebaseAuthStream`, ni el `invalidateSelf()` de `AuthNotifier.cerrarSesion` tocan ESTE
/// provider (cada uno reconstruye su propio provider, no éste). Un `autoDispose` o un campo en
/// la instancia de PerfilSesion sí se reiniciarían — por eso vive en un provider keepAlive
/// aparte, igual que el estado del guard en [CicloSyncUi]. No persiste: un proceso nuevo arranca
/// en `false`.
@Riverpod(keepAlive: true)
ResolucionSesionProceso resolucionSesionProceso(ResolucionSesionProcesoRef ref) =>
    ResolucionSesionProceso();

@riverpod
class PerfilSesion extends _$PerfilSesion {
  @override
  Future<ResultadoSesion> build() async {
    final usuario = await ref.watch(firebaseAuthStreamProvider.future);
    final dao = ref.read(usuarioActivoDaoProvider);
    final storage = ref.read(secureStorageProvider);

    // CTT-147: ¿es la PRIMERA resolución de la sesión en este proceso? Se lee ANTES de marcar y
    // se marca ya (haya o no usuario), para que la próxima resolución —p. ej. el null que emite
    // signOut en la carrera del logout— NO active la fase 1.
    final resolucion = ref.read(resolucionSesionProcesoProvider);
    final esPrimeraResolucion = !resolucion.yaResolvio;
    resolucion.yaResolvio = true;

    if (usuario == null) {
      // CTT-147 fase 1 (detección), ANTES de dao.limpiar(): si se activa, NO se limpia
      // usuario_activo (se preserva el fallback offline de CTT-138; el dueño de la cola es
      // CTT-123). Si no se activa, se mantiene el logout real de siempre.
      if (await _defensaFase1(storage, esPrimeraResolucion: esPrimeraResolucion)) {
        return const ResultadoSesion.requiereSanar();
      }
      // Logout real: Firebase ya no tiene usuario. Se limpia el perfil local.
      await dao.limpiar();
      return const ResultadoSesion.sinSesion();
    }

    // CTT-147: Firebase tiene usuario = login exitoso → olvida "recién sanado".
    await _olvidarRecienSanado();

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

  // ── CTT-147: defensa en dos fases ──────────────────────────────────────────

  /// Fase 1: arma el controlador y lo ejecuta. Todo envuelto en try/catch: un fallo de la
  /// defensa (p. ej. sin path_provider en un test) NUNCA debe impedir el arranque; se cae al
  /// comportamiento de logout real.
  Future<bool> _defensaFase1(
    SecureStorageService storage, {
    required bool esPrimeraResolucion,
  }) async {
    try {
      final io = await crearDefensaSesionIo();
      final syncDao = ref.read(syncDaoProvider);
      return await io.defensa.ejecutarFase1(
        esPrimeraResolucion: esPrimeraResolucion,
        hayUsuarioFirebase: false, // esta rama es solo `usuario == null`
        hayToken: (await storage.obtenerToken()) != null,
        contarPendientes: syncDao.contarNoTerminales,
        limpiarToken: storage.eliminarToken,
        registrarEvento: _registrarEventoIrrecuperable,
      );
    } catch (e, st) {
      _registrarErrorDefensa(e, st);
      return false;
    }
  }

  /// Login exitoso (Firebase tiene usuario): quita la marca "recién sanado". Best-effort.
  Future<void> _olvidarRecienSanado() async {
    try {
      final io = await crearDefensaSesionIo();
      io.defensa.alLoginExitoso();
    } catch (e, st) {
      _registrarErrorDefensa(e, st);
    }
  }

  /// Evento no fatal en Crashlytics. El modelo del dispositivo lo adjunta Crashlytics en sus
  /// metadatos; la versión de Android se agrega como clave. Si no se puede enviar ahora, queda
  /// encolado para el próximo arranque.
  void _registrarEventoIrrecuperable() {
    try {
      final cr = FirebaseCrashlytics.instance;
      cr.setCustomKey('android_version', Platform.operatingSystemVersion);
      cr.recordError(
        'sesion_firebase_irrecuperable',
        StackTrace.current,
        reason: 'sesion_firebase_irrecuperable',
        fatal: false,
      );
    } catch (_) {
      // La telemetría nunca debe romper la defensa ni el arranque.
    }
  }

  void _registrarErrorDefensa(Object error, StackTrace stack) {
    try {
      FirebaseCrashlytics.instance
          .recordError(error, stack, reason: 'defensa_sesion', fatal: false);
    } catch (_) {
      // Sin Firebase (tests) o sin red: se ignora.
    }
  }
}
