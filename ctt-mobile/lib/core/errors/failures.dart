/// failures.dart — Clases de fallo del dominio.
///
/// Los repositorios devuelven Failure en vez de lanzar excepciones.
/// Esto hace el manejo de errores explícito y testeable.

sealed class Failure {
  const Failure(this.mensaje);
  final String mensaje;
}

/// Error de red o API no disponible.
class FalloRed extends Failure {
  const FalloRed([super.mensaje = 'Sin conexión o servidor no disponible.']);
}

/// El servidor respondió pero con error HTTP conocido.
class FalloServidor extends Failure {
  const FalloServidor(super.mensaje, {this.codigoHttp});
  final int? codigoHttp;
}

/// Token expirado o credenciales inválidas (HTTP 401).
class FalloNoAutorizado extends Failure {
  const FalloNoAutorizado([super.mensaje = 'Sesión expirada. Inicia sesión nuevamente.']);
}

/// Acción no permitida para el rol actual (HTTP 403).
class FalloSinPermiso extends Failure {
  const FalloSinPermiso([super.mensaje = 'No tienes permiso para esta acción.']);
}

/// Datos de entrada inválidos (HTTP 422 de FastAPI).
class FalloValidacion extends Failure {
  const FalloValidacion(super.mensaje);
}

/// Error de lectura/escritura en base de datos local (Drift).
class FalloBaseDatosLocal extends Failure {
  const FalloBaseDatosLocal([super.mensaje = 'Error al acceder a datos locales.']);
}

/// Transición de estado inválida (violación máquina de estados Sección 6.2).
class FalloTransicionInvalida extends Failure {
  const FalloTransicionInvalida(super.mensaje);
}

/// Error al procesar o comprimir imagen para evidencia.
class FalloImagen extends Failure {
  const FalloImagen([super.mensaje = 'Error al procesar la imagen.']);
}

/// Error desconocido — incluir detalle para Crashlytics.
class FalloDesconocido extends Failure {
  const FalloDesconocido([super.mensaje = 'Ocurrió un error inesperado.']);
}
