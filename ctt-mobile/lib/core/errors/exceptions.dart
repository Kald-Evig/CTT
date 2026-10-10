/// exceptions.dart — Excepciones de la capa de datos.
///
/// La capa de datos lanza excepciones; los repositorios las capturan y las
/// convierten en Failure (ver failures.dart). Separar excepciones de failures
/// permite testear cada capa de forma independiente.
library;

class ExcepcionRed implements Exception {
  const ExcepcionRed([this.mensaje = 'Error de red.']);
  final String mensaje;
  @override
  String toString() => 'ExcepcionRed: $mensaje';
}

class ExcepcionNoAutorizado implements Exception {
  const ExcepcionNoAutorizado([this.mensaje = 'No autorizado.']);
  final String mensaje;
  @override
  String toString() => 'ExcepcionNoAutorizado: $mensaje';
}

class ExcepcionSinPermiso implements Exception {
  const ExcepcionSinPermiso([this.mensaje = 'Sin permiso.']);
  final String mensaje;
  @override
  String toString() => 'ExcepcionSinPermiso: $mensaje';
}

/// 403 con un `code` de cuenta en el cuerpo (p. ej. `usuario_deshabilitado`,
/// `tenant_suspendido`). A diferencia de [ExcepcionSinPermiso] (403 de permiso sobre
/// un recurso), esto significa que la SESIÓN ya no es válida → la app debe ir a login
/// (CTT-138). El backend emitirá estos `code` con CTT-88; el cliente ya los clasifica.
class ExcepcionCuentaRevocada implements Exception {
  const ExcepcionCuentaRevocada(this.code,
      [this.mensaje = 'La cuenta fue deshabilitada o la sesión revocada.']);
  final String code;
  final String mensaje;
  @override
  String toString() => 'ExcepcionCuentaRevocada($code): $mensaje';
}

class ExcepcionValidacion implements Exception {
  const ExcepcionValidacion(this.mensaje);
  final String mensaje;
  @override
  String toString() => 'ExcepcionValidacion: $mensaje';
}

class ExcepcionServidor implements Exception {
  const ExcepcionServidor(this.mensaje, {this.codigoHttp});
  final String mensaje;
  final int? codigoHttp;
  @override
  String toString() => 'ExcepcionServidor($codigoHttp): $mensaje';
}

class ExcepcionBaseDatos implements Exception {
  const ExcepcionBaseDatos([this.mensaje = 'Error de base de datos local.']);
  final String mensaje;
  @override
  String toString() => 'ExcepcionBaseDatos: $mensaje';
}
