/// environment.dart — Configuración de entorno de la app.
///
/// La URL base se configura aquí. Para cambiarla sin recompilar se puede usar
/// --dart-define=API_BASE_URL=https://... al hacer flutter run/build.
/// Nunca hardcodear credenciales ni tokens en este archivo.
library;

class Entorno {
  Entorno._();

  /// URL base de la API. Valor por defecto apunta al emulador Android
  /// (10.0.2.2 es el host desde el emulador). Sobreescribir con:
  ///   flutter run --dart-define=API_BASE_URL=https://api.ctt.cl
  static const String urlBaseApi = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Modo de autenticación. Determina de dónde sale el token (incluido el del
  /// rescate CTT-130 4b): 'mock' → el UID guardado en SecureStorage; 'firebase' →
  /// token fresco vía getIdToken(true). Sobreescribir con:
  ///   flutter run --dart-define=AUTH_MODE=firebase
  static const String modoAuth = String.fromEnvironment(
    'AUTH_MODE',
    defaultValue: 'mock',
  );

  /// Tiempos máximos por fase de un request HTTP (CTT-142). Fuente ÚNICA para TODOS los Dio
  /// (interactivo, cola/headless vía crearDioSync, rescate), aplicados en [opcionesBaseDio].
  /// - Conexión 5 s: el camino interactivo falla rápido cuando no hay red (3G débil en obra),
  ///   en vez de bloquear 30 s.
  /// - Envío (sendTimeout) 15 s: acota el envío del cuerpo; en los GET sin cuerpo es no-op.
  /// - Recepción 30 s: holgado para la respuesta del servidor.
  static const Duration timeoutConexion = Duration(seconds: 5);
  static const Duration timeoutEnvio = Duration(seconds: 15);
  static const Duration timeoutRecepcion = Duration(seconds: 30);

  /// Detectado automáticamente por Flutter en tiempo de compilación.
  static bool get esDebug => _esDebug;
  static bool get esRelease => _esRelease;
  static bool get esProfile => _esProfile;

  // ignore: do_not_use_environment
  static const bool _esDebug = bool.fromEnvironment('dart.vm.product') == false &&
      bool.fromEnvironment('dart.vm.profile') == false;
  // ignore: do_not_use_environment
  static const bool _esRelease = bool.fromEnvironment('dart.vm.product');
  // ignore: do_not_use_environment
  static const bool _esProfile = bool.fromEnvironment('dart.vm.profile');
}
