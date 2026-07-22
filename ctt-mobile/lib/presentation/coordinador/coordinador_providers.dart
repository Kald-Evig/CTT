library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/data/repositories/coordinador_repository.dart';
import 'package:ctt_mobile/data/repositories/residente_repository.dart';
import 'package:ctt_mobile/domain/entities/coordinador_models.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';

part 'coordinador_providers.g.dart';

// ── Dashboard (CTT-42) ───────────────────────────────────────────────────────

@riverpod
Future<List<DashboardProyecto>> dashboardProyectos(
  DashboardProyectosRef ref,
) =>
    ref.watch(coordinadorRepositoryProvider).listarDashboard();

@riverpod
Future<List<HistorialProyectoEntrada>> historialProyecto(
  HistorialProyectoRef ref,
  String proyectoId,
) =>
    ref.watch(coordinadorRepositoryProvider).listarHistorialProyecto(proyectoId);

// ── Miembros de proyecto (CTT-44) ────────────────────────────────────────────

@riverpod
Future<List<MiembroProyecto>> miembrosProyecto(
  MiembrosProyectoRef ref,
  String proyectoId,
) =>
    ref.watch(coordinadorRepositoryProvider).getMiembros(proyectoId);

// ── Conflictos ────────────────────────────────────────────────────────────────

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
