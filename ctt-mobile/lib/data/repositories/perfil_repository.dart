/// perfil_repository.dart — Acceso al endpoint GET /me del backend.
library;

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/domain/entities/perfil_usuario.dart';

part 'perfil_repository.g.dart';

@riverpod
PerfilRepository perfilRepository(PerfilRepositoryRef ref) =>
    PerfilRepository(ref.watch(dioClientProvider));

class PerfilRepository {
  const PerfilRepository(this._dio);

  final Dio _dio;

  Future<PerfilUsuario> obtenerPerfil() async {
    final respuesta = await _dio.get<Map<String, dynamic>>('/me');
    return PerfilUsuario.fromJson(respuesta.data!);
  }
}
