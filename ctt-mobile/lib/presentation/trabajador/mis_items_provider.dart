/// mis_items_provider.dart — Providers de datos para el Trabajador.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/repositories/items_repository.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

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

/// IDs de ítems con cambios pendientes de sincronizar — Stream REACTIVO (Drift
/// `.watch()`): el indicador de las listas se refresca solo al cambiar la cola, sin
/// re-montar la pantalla (CTT-103 D6-R).
@riverpod
Stream<Set<String>> itemsConSyncPendiente(ItemsConSyncPendienteRef ref) =>
    ref.watch(syncDaoProvider).observarIdsPendienteSet();

/// entidad_id → estado de revisión (rechazada/en_revision) para el badge de sync —
/// Stream REACTIVO. Consulta aparte de [itemsConSyncPendiente] (A3).
@riverpod
Stream<Map<String, EstadoSyncLocal>> itemsEnRevision(ItemsEnRevisionRef ref) =>
    ref.watch(syncDaoProvider).observarEstadoRevisionPorItem();
