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
            comentario: comentario,
            descripcionProblema: descripcionProblema,
          );

      switch (resultado.estado) {
        case EstadoSyncLocal.sincronizado:
          // El servidor aceptó: el estado optimista YA es el correcto. Refrescar la
          // lista para que refleje el nuevo estado.
          ref.invalidate(itemsProyectoProvider);
        case EstadoSyncLocal.esperandoResolucion:
        case EstadoSyncLocal.rechazada:
          // El servidor no aceptó el cambio: revertir al estado anterior.
          state = AsyncData(estadoAnterior);
        default:
          // pendiente / otros: mantener el optimista hasta que el ciclo sincronice.
          break;
      }

      return resultado;
    } catch (e) {
      // Excepción inesperada (401, 403, 5xx): revertir.
      state = AsyncData(estadoAnterior);
      rethrow;
    }
  }

  ItemResidente _conNuevoEstado(ItemResidente item, String nuevoEstado) =>
      ItemResidente(
        id: item.id,
        proyectoId: item.proyectoId,
        parentItemId: item.parentItemId,
        nivelProfundidad: item.nivelProfundidad,
        nombre: item.nombre,
        descripcion: item.descripcion,
        asignadoA: item.asignadoA,
        asignadoNombre: item.asignadoNombre,
        estado: nuevoEstado,
        fechaLimite: item.fechaLimite,
      );
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
