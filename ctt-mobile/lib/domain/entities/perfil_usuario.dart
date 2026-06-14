/// perfil_usuario.dart — Entidades del perfil del usuario autenticado.
///
/// Mapea la respuesta de GET /me. No incluye RUT ni datos sensibles.
library;

import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

/// Una empresa a la que pertenece el usuario (ya filtrada: activa y no suspendida).
class EmpresaPerfil {
  const EmpresaPerfil({
    required this.empresaId,
    required this.empresaNombre,
    required this.rol,
  });

  final String empresaId;
  final String empresaNombre;
  final RolUsuario rol;

  factory EmpresaPerfil.fromJson(Map<String, dynamic> json) => EmpresaPerfil(
        empresaId: json['empresa_id'] as String,
        empresaNombre: json['empresa_nombre'] as String,
        rol: RolUsuario.fromString(json['rol'] as String),
      );
}

/// Perfil completo del usuario autenticado, incluyendo sus empresas activas.
class PerfilUsuario {
  const PerfilUsuario({
    required this.id,
    required this.nombreCompleto,
    required this.email,
    required this.esSuperAdmin,
    required this.empresas,
  });

  final String id;
  final String nombreCompleto;
  final String email;
  final bool esSuperAdmin;

  /// Lista de empresas activas. Vacía es válido (super_admin sin empresa, o usuario nuevo).
  final List<EmpresaPerfil> empresas;

  factory PerfilUsuario.fromJson(Map<String, dynamic> json) {
    final u = json['usuario'] as Map<String, dynamic>;
    final lista = json['empresas'] as List<dynamic>;
    return PerfilUsuario(
      id: u['id'] as String,
      nombreCompleto: u['nombre_completo'] as String,
      email: u['email'] as String,
      esSuperAdmin: u['es_super_admin'] as bool,
      empresas: lista
          .map((e) => EmpresaPerfil.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
