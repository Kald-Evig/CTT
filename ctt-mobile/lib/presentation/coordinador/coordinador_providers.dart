library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/data/repositories/coordinador_repository.dart';
import 'package:ctt_mobile/data/repositories/residente_repository.dart';
import 'package:ctt_mobile/domain/entities/coordinador_models.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';

part 'coordinador_providers.g.dart';

@riverpod
Future<List<ConflictoSync>> conflictosPendientes(ConflictosPendientesRef ref) =>
    ref.watch(coordinadorRepositoryProvider).listarConflictos(estado: 'pendiente');

/// Carga el ítem para mostrar su nombre en la card de conflicto.
/// Devuelve null si el ítem no existe o hay error — la card muestra el item_id como fallback.
@riverpod
Future<ItemResidente?> itemParaConflicto(
  ItemParaConflictoRef ref,
  String itemId,
) async {
  try {
    return await ref.watch(residenteRepositoryProvider).obtenerItem(itemId);
  } catch (_) {
    return null;
  }
}
