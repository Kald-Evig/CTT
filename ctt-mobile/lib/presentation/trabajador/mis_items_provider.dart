/// mis_items_provider.dart — Providers de datos para el Trabajador.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/data/local/daos/items_cache_dao.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/repositories/items_repository.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'mis_items_provider.g.dart';

/// Ítems del Trabajador con el estado MOSTRADO (base + overlay, CTT-144). Stream:
/// primero dispara el pull de red (que escribe la base en `items_cache`; offline cae a
/// la cache) y luego emite el overlay reactivo, que se refresca solo cuando cambia la
/// cola, sin re-pull.
@riverpod
Stream<List<ItemConOverlay>> misItems(MisItemsRef ref) async* {
  final storage = ref.watch(secureStorageProvider);
  final usuarioId = await storage.obtenerUsuarioId() ?? '';
  // CTT-143 v8 (opción A): la lista se filtra por (usuario, empresa activa).
  final empresaId = await storage.obtenerEmpresaId() ?? '';
  await ref.watch(itemsRepositoryProvider).obtenerMisItems(usuarioId);
  yield* ref
      .watch(itemsCacheDaoProvider)
      .observarAsignadosConOverlay(usuarioId, empresaId);
}

/// Detalle de un ítem con el estado MOSTRADO (base + overlay). Stream reactivo: los
/// botones de transición (detalle_item_screen) derivan de este estado.
@riverpod
Stream<ItemConOverlay?> itemDetalle(ItemDetalleRef ref, String itemId) =>
    ref.watch(itemsCacheDaoProvider).observarPorIdConOverlay(itemId);

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
