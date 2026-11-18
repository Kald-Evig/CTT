/// mis_items_provider.dart — Providers de datos para el Trabajador.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/data/local/daos/items_cache_dao.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/repositories/items_repository.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/domain/grupo_accion.dart';

part 'mis_items_provider.g.dart';

/// Ítems del Trabajador con el estado MOSTRADO (base + overlay, CTT-144). Stream:
/// primero dispara el pull de red (que escribe la base en `items_cache`; offline cae a
/// la cache) y luego emite el overlay reactivo, que se refresca solo cuando cambia la
/// cola, sin re-pull.
@riverpod
Stream<List<ItemConOverlay>> misItems(MisItemsRef ref) async* {
  final storage = ref.watch(secureStorageProvider);
  final usuarioId = await storage.obtenerUsuarioId();
  final empresaId = await storage.obtenerEmpresaId();
  // CTT-143 v8 (opción A): la partición es (usuario, empresa activa). Sin usuario o sin
  // empresa NO hay partición válida: no se hace pull ni se lista — NUNCA '' como empresa
  // (vaciaría/mezclaría la caché). El router ya redirige a la selección de empresa cuando
  // corresponde (multiempresa); este caso es transitorio/borde y se muestra lista vacía.
  if (usuarioId == null ||
      usuarioId.isEmpty ||
      empresaId == null ||
      empresaId.isEmpty) {
    yield const <ItemConOverlay>[];
    return;
  }
  // El pull estampa la empresa activa y retira dentro de (usuario, empresa); el listado se
  // lee reactivo y aislado por empresa. CTT-162: el orden se aplica acá (una sola fuente),
  // no en el DAO.
  await ref.watch(itemsRepositoryProvider).obtenerMisItems(usuarioId, empresaId);
  yield* ref
      .watch(itemsCacheDaoProvider)
      .observarAsignadosConOverlay(usuarioId, empresaId)
      .map(ordenarMisItems);
}

/// Grupo de un ítem de "Mis ítems" (CTT-162) — FUENTE ÚNICA, la usan [ordenarMisItems] y
/// la lista (`mis_items_screen.dart`). Fija rol Trabajador y esAsignado: true (todos los
/// ítems de Mis ítems son suyos y asignados, misma convención que el detalle). Un
/// `estadoMostrado` desconocido (un estado nuevo del backend que esta versión aún no
/// conoce) NO lanza: cae en "Esperando a otros", como la lista toleraba antes de CTT-162
/// (el badge igual muestra el crudo). Ver [EstadoItem.tryFromString].
GrupoAccion grupoDeMiItem(ItemConOverlay item) {
  final estado = EstadoItem.tryFromString(item.estadoMostrado);
  if (estado == null) return GrupoAccion.esperaAOtros;
  return grupoAccion(estado, rol: RolUsuario.trabajador, esAsignado: true);
}

/// Ordena "Mis ítems" (CTT-162), función PURA — fuente única del orden de la lista:
/// proyecto (`proyectoNombre` ASC, desempate `proyectoId`) → grupo de acción
/// ([GrupoAccion], su `.index`) → `fecha_limite` ASC (los sin fecha al final) → `nombre`
/// → `id`. El grupo sale de [grupoDeMiItem] (rol Trabajador, esAsignado: true — misma
/// convención que el detalle). `fecha_limite` es ISO 'YYYY-MM-DD', así que el orden
/// lexicográfico coincide con el cronológico (igual que el ORDER BY de CTT-145 que
/// reemplaza).
List<ItemConOverlay> ordenarMisItems(List<ItemConOverlay> items) {
  // Precalcula el grupo de cada ítem (evita recomputar accionesPermitidas en el comparador).
  final grupoPorId = <String, int>{
    for (final it in items) it.id: grupoDeMiItem(it).index,
  };
  final ordenada = [...items];
  ordenada.sort((a, b) {
    final pNombre = a.proyectoNombre.compareTo(b.proyectoNombre);
    if (pNombre != 0) return pNombre;
    final pId = a.proyectoId.compareTo(b.proyectoId);
    if (pId != 0) return pId;
    final g = grupoPorId[a.id]!.compareTo(grupoPorId[b.id]!);
    if (g != 0) return g;
    final fa = a.fechaLimite;
    final fb = b.fechaLimite;
    if (fa == null && fb != null) return 1; // sin fecha → al final
    if (fa != null && fb == null) return -1;
    if (fa != null && fb != null) {
      final f = fa.compareTo(fb);
      if (f != 0) return f;
    }
    final n = a.nombre.compareTo(b.nombre);
    if (n != 0) return n;
    return a.id.compareTo(b.id);
  });
  return ordenada;
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
