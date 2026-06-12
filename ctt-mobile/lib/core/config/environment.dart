/// environment.dart — Configuración de entorno de la app.
///
/// La URL base se configura aquí. Para cambiarla sin recompilar se puede usar
/// --dart-define=API_BASE_URL=https://... al hacer flutter run/build.
/// Nunca hardcodear credenciales ni tokens en este archivo.

class Entorno {
  Entorno._();

  /// URL base de la API. Valor por defecto apunta al emulador Android
  /// (10.0.2.2 es el host desde el emulador). Sobreescribir con:
  ///   flutter run --dart-define=API_BASE_URL=https://api.ctt.cl
  static const String urlBaseApi = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Tiempo máximo de conexión y recepción para requests HTTP.
  static const Duration timeoutConexion = Duration(seconds: 30);
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
