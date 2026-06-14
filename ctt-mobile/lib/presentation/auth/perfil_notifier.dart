/// perfil_notifier.dart — Estado del perfil del usuario autenticado.
///
/// Observa el stream de Firebase Auth y carga /me automáticamente al login.
/// Al logout, Firebase emite null y el notifier retorna null sin hacer nada más.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/data/local/daos/usuario_activo_dao.dart';
import 'package:ctt_mobile/data/repositories/perfil_repository.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';

part 'perfil_notifier.g.dart';

@riverpod
class PerfilSesion extends _$PerfilSesion {
  @override
  Future<PerfilUsuario?> build() async {
    final usuario = await ref.watch(firebaseAuthStreamProvider.future);
    if (usuario == null) {
      // Limpiar perfil local al cerrar sesión.
      await ref.read(usuarioActivoDaoProvider).limpiar();
      return null;
    }

    final repo = ref.read(perfilRepositoryProvider);
    final storage = ref.read(secureStorageProvider);
    final dao = ref.read(usuarioActivoDaoProvider);
    final perfil = await repo.obtenerPerfil();

    final empresa = perfil.empresas.isNotEmpty ? perfil.empresas.first : null;

    // Persistir empresa activa para AuthInterceptor (X-Empresa-Id).
    if (empresa != null) {
      await storage.guardarEmpresaId(empresa.empresaId);
    }
    await storage.guardarUsuarioId(perfil.id);

    // Persistir sesión en Drift para acceso offline.
    await dao.guardarPerfil(
      perfil: perfil,
      empresaId: empresa?.empresaId ?? '',
      empresaNombre: empresa?.empresaNombre ?? '',
      rolActual: empresa?.rol.valor ?? '',
    );

    return perfil;
  }
}
