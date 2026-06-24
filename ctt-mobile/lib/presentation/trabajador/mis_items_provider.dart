/// mis_items_provider.dart — Providers de datos para el Trabajador.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
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

/// IDs de ítems con cambios pendientes de sincronizar.
/// Usado para el indicador visual de sincronización en las listas.
@riverpod
Future<Set<String>> itemsConSyncPendiente(ItemsConSyncPendienteRef ref) =>
    ref.watch(syncDaoProvider).obtenerIdsPendienteSet();
