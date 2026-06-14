/// empresa_activa_notifier.dart — Empresa en la que el usuario está operando.
///
/// Cuando el perfil tiene una sola empresa, se auto-selecciona.
/// Cuando hay múltiples, el estado empieza en null hasta que el usuario
/// elige en SeleccionEmpresaScreen; el router detecta el null y redirige.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';
import 'package:ctt_mobile/presentation/auth/perfil_notifier.dart';

part 'empresa_activa_notifier.g.dart';

@riverpod
class EmpresaActiva extends _$EmpresaActiva {
  @override
  String? build() {
    final perfil = ref.watch(perfilSesionProvider).valueOrNull;
    if (perfil == null) return null;
    // Una sola empresa: auto-selección transparente.
    if (perfil.empresas.length == 1) return perfil.empresas.first.empresaId;
    // Múltiples empresas: espera a que el usuario elija.
    return null;
  }

  /// Persiste la empresa elegida y actualiza el estado para que el router redirija.
  Future<void> seleccionar(EmpresaPerfil empresa) async {
    await ref.read(secureStorageProvider).guardarEmpresaId(empresa.empresaId);
    state = empresa.empresaId;
  }
}
