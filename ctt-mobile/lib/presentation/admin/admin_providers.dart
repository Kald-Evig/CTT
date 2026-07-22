library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/data/repositories/admin_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';

part 'admin_providers.g.dart';

/// Family: incluirInactivos=false → solo activos (default).
///         incluirInactivos=true  → activos + inactivos (Admin UI).
@riverpod
Future<List<UsuarioEmpresa>> usuariosAdmin(
  UsuariosAdminRef ref, {
  bool incluirInactivos = false,
}) =>
    ref
        .watch(adminRepositoryProvider)
        .listarUsuarios(incluirInactivos: incluirInactivos);
