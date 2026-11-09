/// defensa_sesion.dart — CTT-147. Defensa en dos fases contra el estado roto de
/// Firebase Auth (Store/crypto restaurados por Auto Backup sin su clave del Keystore).
///
/// La LÓGICA vive acá, en un controlador puro e inyectable ([DefensaSesion]); los
/// widgets, `PerfilSesion.build` y `main()` solo lo llaman. El estado (las dos marcas)
/// vive en archivos del directorio de soporte de la app, para poder leerse ANTES de
/// `Firebase.initializeApp` y SIN SecureStorage (fase 2 corre en `main()`).
///
/// Dos fases, idempotentes (hechos medidos en ctt147_exp_*):
///   • Fase 1 (detección, `PerfilSesion.build`, antes de `dao.limpiar()`): si Firebase
///     está en null + hay `_ctt_jwt` + no está la marca "recién sanado", marca "sanar",
///     registra telemetría y —si la cola está vacía— limpia el token. La UI va a una
///     pantalla bloqueante (Cerrar CTT). Borrar los archivos con el proceso vivo NO sirve
///     (exp i): por eso se sana en el próximo arranque.
///   • Fase 2 (sanar, `main()`, antes de `Firebase.initializeApp`, solo isolate de UI): si
///     está la marca "sanar", borra `com.google.firebase.auth.api.{Store,crypto}.*.xml`,
///     pone "recién sanado" y quita "sanar". Firebase recrea sus archivos recién en el
///     primer login (exp ii), así que borrarlos antes del init deja el arranque limpio.
///   • El login exitoso quita "recién sanado".
///
/// Ningún error de la defensa debe impedir el arranque: [sanarFase2] no relanza, y los
/// llamadores envuelven todo en try/catch.
library;

/// ¿El nombre de archivo es uno de los dos XML de Firebase Auth que hay que borrar?
/// `Store.<appid>.xml` (sesión cifrada) o `crypto.<appid>.xml` (keyset de Tink).
bool esArchivoFirebaseAuth(String nombre) =>
    (nombre.startsWith('com.google.firebase.auth.api.Store.') ||
        nombre.startsWith('com.google.firebase.auth.api.crypto.')) &&
    nombre.endsWith('.xml');

/// Almacén de las dos marcas de la defensa. La implementación real ([MarcasDefensaArchivo])
/// usa archivos; se inyecta un fake en los tests. Síncrono a propósito: la fase 2 lo lee en
/// `main()` antes de cualquier await de Firebase/SecureStorage.
abstract interface class MarcasDefensa {
  bool get haySanar;
  bool get hayRecienSanado;
  void marcarSanar();
  void quitarSanar();
  void marcarRecienSanado();
  void quitarRecienSanado();
}

/// Acceso a los archivos de `shared_prefs/` (listar nombres y borrar). La implementación real
/// ([ArchivosSharedPrefsIo]) resuelve la ruta a partir del directorio de la app; se inyecta un
/// fake en los tests.
abstract interface class ArchivosSharedPrefs {
  List<String> nombres();
  void borrar(String nombre);
}

/// Controlador puro de la defensa. Recibe sus dependencias por constructor/parámetro para
/// testearse sin Riverpod, sin Firebase y sin sistema de archivos real.
class DefensaSesion {
  DefensaSesion(this._marcas);

  final MarcasDefensa _marcas;

  /// Decisión pura de la fase 1: ¿activar la defensa? Se activa solo si Firebase no tiene
  /// usuario, hay token y NO venimos de sanar recién (evita el bucle).
  bool debeActivarFase1({
    required bool hayUsuarioFirebase,
    required bool hayToken,
  }) =>
      !hayUsuarioFirebase && hayToken && !_marcas.hayRecienSanado;

  /// Fase 1 completa: evalúa y, si corresponde, marca "sanar", registra el evento y —si la
  /// cola está vacía— limpia el token (si no, se conserva para que el headless siga drenando;
  /// la propiedad de la cola es de CTT-123). Devuelve true si se activó (la UI debe mostrar la
  /// pantalla bloqueante). No llama a `dao.limpiar()`: eso lo decide el llamador según el
  /// resultado (si se activa, NO se limpia `usuario_activo`).
  Future<bool> ejecutarFase1({
    required bool hayUsuarioFirebase,
    required bool hayToken,
    required Future<int> Function() contarPendientes,
    required Future<void> Function() limpiarToken,
    required void Function() registrarEvento,
  }) async {
    if (!debeActivarFase1(
      hayUsuarioFirebase: hayUsuarioFirebase,
      hayToken: hayToken,
    )) {
      return false;
    }
    _marcas.marcarSanar();
    registrarEvento();
    if (await contarPendientes() == 0) {
      await limpiarToken();
    }
    return true;
  }

  /// Fase 2: si está la marca "sanar", borra los dos XML de Firebase Auth de [archivos],
  /// pone "recién sanado" y quita "sanar". Devuelve cuántos borró.
  ///
  /// Nunca relanza: si el borrado falla, NO pone "recién sanado" ni quita "sanar" (la marca
  /// queda para reintentar en el próximo arranque) y reporta por [alError]. Devuelve 0.
  int sanarFase2(
    ArchivosSharedPrefs archivos, {
    void Function(Object error, StackTrace stack)? alError,
  }) {
    if (!_marcas.haySanar) return 0;
    try {
      final aBorrar = archivos.nombres().where(esArchivoFirebaseAuth).toList();
      for (final nombre in aBorrar) {
        archivos.borrar(nombre);
      }
      _marcas.marcarRecienSanado();
      _marcas.quitarSanar();
      return aBorrar.length;
    } catch (e, st) {
      // La marca "sanar" queda intacta para reintentar; la defensa no impide el arranque.
      alError?.call(e, st);
      return 0;
    }
  }

  /// Login exitoso: olvida "recién sanado" (ya se superó la ventana anti-bucle).
  void alLoginExitoso() => _marcas.quitarRecienSanado();
}
