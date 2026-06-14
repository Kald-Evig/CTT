/// perfil_notifier.dart — Estado del perfil del usuario autenticado.
///
/// Observa el stream de Firebase Auth y carga /me automáticamente al login.
/// Al logout, Firebase emite null y el notifier retorna null sin hacer nada más.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/data/repositories/perfil_repository.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';

part 'perfil_notifier.g.dart';

@riverpod
class PerfilSesion extends _$PerfilSesion {
  @override
  Future<PerfilUsuario?> build() async {
    // Reacciona a cada cambio del stream de Firebase (login / logout / token refresh).
    final usuario = await ref.watch(firebaseAuthStreamProvider.future);
    if (usuario == null) return null;

    final repo = ref.read(perfilRepositoryProvider);
    final storage = ref.read(secureStorageProvider);
    final perfil = await repo.obtenerPerfil();

    // Persistir empresa activa para que AuthInterceptor adjunte X-Empresa-Id.
    // Si el usuario pertenece a múltiples empresas, se usa la primera
    // (TODO: pantalla de selección de empresa en Fase 2).
    if (perfil.empresas.isNotEmpty) {
      await storage.guardarEmpresaId(perfil.empresas.first.empresaId);
    }
    await storage.guardarUsuarioId(perfil.id);

    return perfil;
  }
}
