/// residente_providers.dart — Providers de datos para el rol Residente.
///
/// Todos son FutureProviders directos al backend (sin caché local).
/// Los providers parametrizados crean una instancia por combinación de args.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/data/repositories/residente_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';

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

@riverpod
Future<ItemResidente> itemResidente(
  ItemResidenteRef ref,
  String itemId,
) =>
    ref.watch(residenteRepositoryProvider).obtenerItem(itemId);

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
