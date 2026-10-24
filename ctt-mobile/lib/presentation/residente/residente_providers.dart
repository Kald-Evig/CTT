/// residente_providers.dart — Providers de datos para el rol Residente.
///
/// itemResidenteDetalleProvider es un AsyncNotifier (CTT-36):
///   - build() carga el ítem desde el servidor.
///   - transicionar() aplica optimistic UI + llama ResidenteRepository.
///   - Si el servidor acepta: actualiza con datos del servidor.
///   - Si no hay red: mantiene el estado optimista (queda en cola offline).
///   - Si el servidor rechaza: revierte al estado anterior.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/data/local/daos/sync_dao.dart' show ResultadoEspera;
import 'package:ctt_mobile/data/repositories/residente_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'residente_providers.g.dart';

@riverpod
Future<List<ProyectoResidente>> proyectosResidente(
  ProyectosResidenteRef ref,
) =>
    ref.watch(residenteRepositoryProvider).listarProyectos();

/// Family: una instancia por (proyectoId, estadoFiltro).
/// estadoFiltro == null → sin filtro de estado (muestra todos).
@riverpod
Future<List<ItemResidente>> itemsProyecto(
  ItemsProyectoRef ref,
  String proyectoId,
  String? estadoFiltro,
) =>
    ref.watch(residenteRepositoryProvider).listarItemsProyecto(
          proyectoId,
          estadoFiltro: estadoFiltro,
        );

/// Detalle de ítem con optimistic UI y fallback offline (CTT-36).
/// Usar [ItemResidenteDetalleNotifier.transicionar] en vez de llamar al repo directamente.
@riverpod
class ItemResidenteDetalle extends _$ItemResidenteDetalle {
  @override
  Future<ItemResidente> build(String itemId) =>
      ref.watch(residenteRepositoryProvider).obtenerItem(itemId);

  /// Ejecuta una transición de estado con optimistic UI (CTT-148: encolar primero).
  Future<ResultadoEspera> transicionar({
    required String nuevoEstado,
    String? comentario,
    String? descripcionProblema,
  }) async {
    final estadoAnterior = state.valueOrNull;
    if (estadoAnterior == null) {
      return const ResultadoEspera(EstadoSyncLocal.rechazada,
          ultimoError: 'Estado del ítem no disponible.',);
    }

    // Actualización optimista: la UI refleja el cambio al instante.
    state = AsyncData(_conNuevoEstado(estadoAnterior, nuevoEstado));

    try {
      final resultado = await ref.read(residenteRepositoryProvider).transicionarItem(
            estadoAnterior.id,
            nuevoEstado,
            // C2-fix: version del MISMO ItemResidente que el usuario estaba viendo (state),
            // no una re-consulta antes de enviar.
            version: estadoAnterior.version,
            comentario: comentario,
            descripcionProblema: descripcionProblema,
          );

      switch (resultado.estado) {
        case EstadoSyncLocal.sincronizado:
          // El servidor aceptó: el estado optimista YA es el correcto. Se actualiza la
          // version a la del servidor (C3e) para que la PRÓXIMA transición del Residente no
          // salga con la base vencida (su ítem no está en items_cache). Refresca la lista.
          final v = resultado.versionResultante;
          if (v != null) state = AsyncData(state.value!.copyWith(version: v));
          ref.invalidate(itemsProyectoProvider);
        case EstadoSyncLocal.esperandoResolucion:
        case EstadoSyncLocal.rechazada:
          // El servidor no aplicó el cambio: volver al estado anterior. Si el intento trajo
          // una version (409: version_actual), se adopta para no reincidir en el conflicto.
          final v = resultado.versionResultante;
          state = AsyncData(
              v != null ? estadoAnterior.copyWith(version: v) : estadoAnterior);
        default:
          // pendiente/otros: mantener el optimista (con su version; el rebase la corrige al 200).
          break;
      }

      return resultado;
    } catch (e) {
      // Excepción inesperada (401, 403, 5xx): revertir.
      state = AsyncData(estadoAnterior);
      rethrow;
    }
  }

  // Optimista: cambia el estado y PRESERVA la version (C3e: antes la perdía, dejándola
  // null → la 2da transición no podía encolar/rebasear). copyWith conserva el resto.
  ItemResidente _conNuevoEstado(ItemResidente item, String nuevoEstado) =>
      item.copyWith(estado: nuevoEstado);
}

@riverpod
Future<List<ComentarioItem>> comentariosItem(
  ComentariosItemRef ref,
  String itemId,
) =>
    ref.watch(residenteRepositoryProvider).listarComentarios(itemId);

@riverpod
Future<List<EvidenciaItem>> evidenciasItem(
  EvidenciasItemRef ref,
  String itemId,
) =>
    ref.watch(residenteRepositoryProvider).listarEvidencias(itemId);

@riverpod
Future<List<EntradaHistorial>> historialItem(
  HistorialItemRef ref,
  String itemId,
) =>
    ref.watch(residenteRepositoryProvider).listarHistorial(itemId);

@riverpod
Future<List<NotificacionResidente>> notificaciones(
  NotificacionesRef ref,
) =>
    ref.watch(residenteRepositoryProvider).listarNotificaciones();

@riverpod
Future<List<UsuarioEmpresa>> usuariosEmpresa(
  UsuariosEmpresaRef ref,
) =>
    ref.watch(residenteRepositoryProvider).listarUsuarios();

@riverpod
Future<List<UsuarioEmpresa>> usuariosEmpresaPorRoles(
  UsuariosEmpresaPorRolesRef ref,
  List<String> roles,
) =>
    ref.watch(residenteRepositoryProvider).listarUsuarios(roles: roles);
