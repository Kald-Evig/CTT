/// usuario_sesion.dart — Entidad mínima del usuario autenticado.
///
/// Solo contiene los campos disponibles tras el login Firebase.
/// Campos de perfil (rol, empresa) se agregarán cuando el backend exponga /me.
library;

class UsuarioSesion {
  const UsuarioSesion({
    required this.firebaseUid,
    required this.email,
  });

  final String firebaseUid;
  final String email;
}
