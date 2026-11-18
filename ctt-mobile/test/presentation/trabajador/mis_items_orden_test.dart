/// mis_items_orden_test.dart — CTT-162: ordenarMisItems (fuente única del orden de la
/// lista) y los encabezados de grupo en la pantalla.
///
/// Orden: proyecto (proyectoNombre ASC, desempate proyectoId) → grupo (1,2,3) →
/// fecha_limite ASC (sin fecha al final) → nombre → id.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/data/local/daos/items_cache_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/domain/grupo_accion.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_screen.dart';

ItemConOverlay _item({
  required String id,
  required String proyectoId,
  required String proyectoNombre,
  required String estado,
  String? fechaLimite,
  String nombre = 'Ítem',
  String? estadoEnConflicto,
}) =>
    ItemConOverlay(
      base: ItemsCacheTableData(
        id: id,
        proyectoId: proyectoId,
        proyectoNombre: proyectoNombre,
        nivelProfundidad: 0,
        nombre: nombre,
        estadoServidor: estado,
        tieneConflicto: estadoEnConflicto != null,
        fechaLimite: fechaLimite,
        cachadoEn: DateTime.utc(2026, 1, 1),
      ),
      estadoMostrado: estado,
      estadoEnConflicto: estadoEnConflicto,
    );

void main() {
  group('ordenarMisItems', () {
    test(
        'ordena por proyecto → grupo → fecha → nombre → id (3 grupos, 2 proyectos)',
        () {
      // Entregados en orden ARBITRARIO. Proyectos: Alfa (pA) antes que Beta (pB) por nombre.
      final entrada = [
        // Beta
        _item(
            id: 'b1',
            proyectoId: 'pB',
            proyectoNombre: 'Beta',
            estado: 'problema',
            fechaLimite: '2026-02-01'), // grupo 2
        _item(
            id: 'b2',
            proyectoId: 'pB',
            proyectoNombre: 'Beta',
            estado: 'abierto',
            nombre: 'M'), // grupo 1, sin fecha
        // Alfa
        _item(
            id: 'a4',
            proyectoId: 'pA',
            proyectoNombre: 'Alfa',
            estado: 'terminado',
            fechaLimite: '2026-03-01'), // grupo 3
        _item(
            id: 'a1',
            proyectoId: 'pA',
            proyectoNombre: 'Alfa',
            estado: 'abierto',
            fechaLimite: '2026-01-05',
            nombre: 'X'), // grupo 1
        _item(
            id: 'a3',
            proyectoId: 'pA',
            proyectoNombre: 'Alfa',
            estado: 'pendiente_revision',
            nombre: 'Z'), // grupo 2, sin fecha
        _item(
            id: 'a2',
            proyectoId: 'pA',
            proyectoNombre: 'Alfa',
            estado: 'en_progreso',
            fechaLimite: '2026-01-02',
            nombre: 'Y'), // grupo 1, fecha más temprana
        _item(
            id: 'a5',
            proyectoId: 'pA',
            proyectoNombre: 'Alfa',
            estado: 'abierto',
            fechaLimite: '2026-01-05',
            nombre: 'A'), // grupo 1, misma fecha que a1, nombre<
        _item(
            id: 'a6',
            proyectoId: 'pA',
            proyectoNombre: 'Alfa',
            estado: 'abierto',
            fechaLimite: '2026-01-05',
            nombre: 'A'), // igual que a5 → desempata por id
      ];

      final ids = ordenarMisItems(entrada).map((e) => e.id).toList();

      expect(ids, [
        // Alfa: grupo 1 (fecha asc; empate 01-05 → nombre A<X; empate A → id a5<a6), luego
        // grupo 2 (a3, sin fecha), luego grupo 3 (a4).
        'a2', 'a5', 'a6', 'a1', 'a3', 'a4',
        // Beta: grupo 1 (b2), luego grupo 2 (b1).
        'b2', 'b1',
      ]);
    });

    test('sin fecha va al final dentro del grupo', () {
      final ids = ordenarMisItems([
        _item(
            id: 'sin',
            proyectoId: 'p',
            proyectoNombre: 'Obra',
            estado: 'abierto',
            nombre: 'a'),
        _item(
            id: 'con',
            proyectoId: 'p',
            proyectoNombre: 'Obra',
            estado: 'abierto',
            fechaLimite: '2030-12-31',
            nombre: 'z'),
      ]).map((e) => e.id).toList();
      expect(ids,
          ['con', 'sin']); // 'con' (con fecha) antes que 'sin', pese al nombre
    });

    test('un en_progreso con conflicto abierto SIGUE en el grupo 1', () {
      // El conflicto no es input de grupoAccion: un en_progreso queda en grupo 1 igual.
      final conConflicto = _item(
          id: 'c',
          proyectoId: 'p',
          proyectoNombre: 'Obra',
          estado: 'en_progreso',
          estadoEnConflicto: 'pendiente_revision');
      final problema = _item(
          id: 'q', proyectoId: 'p', proyectoNombre: 'Obra', estado: 'problema');
      // El en_progreso (grupo 1) va antes que el problema (grupo 2).
      final ids =
          ordenarMisItems([problema, conConflicto]).map((e) => e.id).toList();
      expect(ids, ['c', 'q']);
    });

    // CTT-162 fix: un estado desconocido (un estado nuevo del backend) NO debe lanzar.
    test('grupoDeMiItem con estado desconocido → esperaAOtros (no lanza)', () {
      final item = _item(
          id: 'f', proyectoId: 'p', proyectoNombre: 'Obra',
          estado: 'estado_futuro');
      expect(grupoDeMiItem(item), GrupoAccion.esperaAOtros);
    });

    test('ordenarMisItems tolera un estado desconocido y ordena el resto', () {
      final ids = ordenarMisItems([
        _item(id: 'term', proyectoId: 'p', proyectoNombre: 'Obra',
            estado: 'terminado'),
        _item(id: 'fut', proyectoId: 'p', proyectoNombre: 'Obra',
            estado: 'estado_futuro'), // desconocido → grupo 2
        _item(id: 'ab', proyectoId: 'p', proyectoNombre: 'Obra',
            estado: 'abierto'),
      ]).map((e) => e.id).toList();
      // abierto (grupo 1) → estado_futuro (grupo 2) → terminado (grupo 3).
      expect(ids, ['ab', 'fut', 'term']);
    });
  });

  group('MisItemsScreen — encabezados de grupo', () {
    Future<void> pump(WidgetTester tester, List<ItemConOverlay> items) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            misItemsProvider.overrideWith((ref) => Stream.value(items)),
            itemsConSyncPendienteProvider
                .overrideWith((ref) => Stream.value(<String>{})),
            itemsEnRevisionProvider.overrideWith(
                (ref) => Stream.value(<String, EstadoSyncLocal>{})),
          ],
          child: const MaterialApp(home: MisItemsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('solo aparecen los encabezados de los grupos con ítems',
        (tester) async {
      await pump(tester, [
        _item(
            id: '1',
            proyectoId: 'p',
            proyectoNombre: 'Obra',
            estado: 'abierto'),
        _item(
            id: '2',
            proyectoId: 'p',
            proyectoNombre: 'Obra',
            estado: 'pendiente_revision'),
        // no hay terminado → "Terminados recientes" NO debe aparecer
      ]);
      expect(find.text('Le toca a ti'), findsOneWidget);
      expect(find.text('Esperando a otros'), findsOneWidget);
      expect(find.text('Terminados recientes'), findsNothing);
    });

    testWidgets(
        'en_progreso con conflicto: bajo "Le toca a ti" y con el chip C4c',
        (tester) async {
      await pump(tester, [
        _item(
            id: 'c',
            proyectoId: 'p',
            proyectoNombre: 'Obra',
            estado: 'en_progreso',
            estadoEnConflicto: 'pendiente_revision'),
      ]);
      expect(find.text('Le toca a ti'), findsOneWidget);
      expect(find.text('Esperando a otros'), findsNothing);
      // Chip de conflicto C4c (no cambia el grupo).
      expect(find.text('En revisión por el Coordinador'), findsOneWidget);
    });

    // CTT-162 fix: un estado desconocido NO rompe el render de la lista.
    testWidgets('un estado desconocido se renderiza (sin ErrorVista) en "Esperando a otros"',
        (tester) async {
      await pump(tester, [
        _item(
            id: 'ab', proyectoId: 'p', proyectoNombre: 'Obra', estado: 'abierto',
            nombre: 'Tarea abierta'),
        _item(
            id: 'fut', proyectoId: 'p', proyectoNombre: 'Obra',
            estado: 'estado_futuro', nombre: 'Tarea futura'),
      ]);
      expect(find.byType(ErrorVista), findsNothing);
      expect(find.text('Le toca a ti'), findsOneWidget);
      expect(find.text('Esperando a otros'), findsOneWidget);
      // El ítem de estado desconocido se muestra igual (no se pierde la lista).
      expect(find.text('Tarea futura'), findsOneWidget);
      expect(find.text('Tarea abierta'), findsOneWidget);
    });
  });
}
