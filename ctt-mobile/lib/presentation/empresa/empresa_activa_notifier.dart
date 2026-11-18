/// empresa_activa_notifier.dart — Empresa en la que el usuario está operando.
///
/// El estado lo resuelve y valida `PerfilSesion.build()` (CTT-164) y lo expone en
/// `ResultadoSesion.empresaActivaId`; acá solo se lee de forma síncrona. Con N=1 queda esa
/// empresa; con N>1 queda la persistida válida, o null (y el router manda a
/// SeleccionEmpresaScreen). `seleccionar()` persiste la elección (SecureStorage + usuario_activo)
/// y actualiza el estado.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/data/local/daos/usuario_activo_dao.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';
import 'package:ctt_mobile/presentation/auth/perfil_notifier.dart';

part 'empresa_activa_notifier.g.dart';

@riverpod
class EmpresaActiva extends _$EmpresaActiva {
  @override
  String? build() {
    // CTT-164: la empresa activa ya la resolvió y validó `PerfilSesion.build()` (online: N=1 o
    // la persistida válida; offline: la de `usuario_activo`). Acá solo se lee de forma síncrona;
    // `_ctt_empresa_id` es la fuente de verdad, ya validada contra el perfil.
    return ref.watch(perfilSesionProvider).valueOrNull?.empresaActivaId;
  }

  /// Persiste la empresa elegida y actualiza el estado para que el router redirija.
  /// Además escribe empresa/nombre/rol en `usuario_activo`, para que el fallback
  /// offline (CTT-138) restaure la ÚLTIMA empresa activa.
  Future<void> seleccionar(EmpresaPerfil empresa) async {
    await ref.read(secureStorageProvider).guardarEmpresaId(empresa.empresaId);
    await ref.read(usuarioActivoDaoProvider).actualizarEmpresaActiva(
          empresaId: empresa.empresaId,
          empresaNombre: empresa.empresaNombre,
          rolActual: empresa.rol.valor,
        );
    state = empresa.empresaId;
  }
}
