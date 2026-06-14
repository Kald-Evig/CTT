/// mis_items_provider.dart — Provider de ítems asignados al trabajador autenticado.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/repositories/items_repository.dart';

part 'mis_items_provider.g.dart';

@riverpod
Future<List<ItemsCacheTableData>> misItems(MisItemsRef ref) async {
  final storage = ref.watch(secureStorageProvider);
  final usuarioId = await storage.obtenerUsuarioId() ?? '';
  return ref.watch(itemsRepositoryProvider).obtenerMisItems(usuarioId);
}

@riverpod
Future<ItemsCacheTableData?> itemDetalle(
  ItemDetalleRef ref,
  String itemId,
) =>
    ref.watch(itemsRepositoryProvider).obtenerDetalle(itemId);
