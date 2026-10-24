/// ctt143_aviso_conflicto_c4c_test.dart — CTT-143 C4c: aviso de conflicto en el detalle
/// del Trabajador.
///
/// Arma: itemDetalleProvider devuelve un ItemConOverlay con estadoEnConflicto (la intención
/// parqueada) y estadoMostrado = la base. Verifica (del código de la pantalla): el aviso
/// muestra los dos estados; los botones salen de la BASE (no de la intención) y no se
/// bloquean; una transición desde el aviso llama a cambiarEstado; y el aviso desaparece
/// cuando estadoEnConflicto se vuelve null (fila descartada/sincronizada).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/data/local/daos/items_cache_dao.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart' show ResultadoEspera;
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/repositories/items_repository.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/trabajador/detalle_item_screen.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';

class _FakeItemsRepository extends Mock implements ItemsRepository {}

ItemConOverlay _item({
  required String estadoServidor,
  required String estadoMostrado,
  String? estadoEnConflicto,
}) =>
    ItemConOverlay(
      base: ItemsCacheTableData(
        id: 'item-1',
        proyectoId: 'p1',
        proyectoNombre: 'Proyecto X',
        nivelProfundidad: 0,
        nombre: 'Tarea de prueba',
        estadoServidor: estadoServidor,
        tieneConflicto: estadoEnConflicto != null,
        updatedAt: DateTime.utc(2026, 1, 1),
        cachadoEn: DateTime.utc(2026, 1, 1),
      ),
      estadoMostrado: estadoMostrado,
      estadoEnConflicto: estadoEnConflicto,
    );

void main() {
  setUpAll(() => registerFallbackValue(EstadoItem.enProgreso));

  Future<void> pump(WidgetTester tester, Stream<ItemConOverlay?> stream,
      {ItemsRepository? repo}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (repo != null) itemsRepositoryProvider.overrideWithValue(repo),
          itemDetalleProvider('item-1').overrideWith((ref) => stream),
        ],
        child: const MaterialApp(home: DetalleItemScreen(itemId: 'item-1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el aviso muestra la intención y la base', (tester) async {
    // Conflicto: la intención fue en_progreso; la base (servidor) sigue abierto.
    await pump(
      tester,
      Stream.value(_item(
        estadoServidor: 'abierto',
        estadoMostrado: 'abierto',
        estadoEnConflicto: 'en_progreso',
      )),
    );
    expect(find.textContaining('Tu cambio: En progreso'), findsOneWidget);
    expect(find.textContaining('Estado actual: Abierto'), findsOneWidget);
    expect(find.textContaining('En revisión por el Coordinador'), findsOneWidget);
  });

  testWidgets('los botones corresponden a la BASE, no a la intención en conflicto',
      (tester) async {
    await pump(
      tester,
      Stream.value(_item(
        estadoServidor: 'abierto',
        estadoMostrado: 'abierto',
        estadoEnConflicto: 'en_progreso',
      )),
    );
    // Base abierto → botón "Iniciar trabajo"; NO los de en_progreso.
    expect(find.text('Iniciar trabajo'), findsOneWidget);
    expect(find.text('Marcar como terminado'), findsNothing);
  });

  testWidgets('una transición desde el aviso se encola (botón no bloqueado)',
      (tester) async {
    final repo = _FakeItemsRepository();
    when(() => repo.cambiarEstado(
          itemId: any(named: 'itemId'),
          nuevoEstado: any(named: 'nuevoEstado'),
        )).thenAnswer(
        (_) async => const ResultadoEspera(EstadoSyncLocal.esperandoResolucion));

    await pump(
      tester,
      Stream.value(_item(
        estadoServidor: 'abierto',
        estadoMostrado: 'abierto',
        estadoEnConflicto: 'en_progreso',
      )),
      repo: repo,
    );
    await tester.tap(find.text('Iniciar trabajo'));
    await tester.pumpAndSettle();

    verify(() => repo.cambiarEstado(
          itemId: 'item-1',
          nuevoEstado: EstadoItem.enProgreso,
        )).called(1);
  });

  testWidgets('el aviso desaparece cuando la fila se cierra (estadoEnConflicto null)',
      (tester) async {
    final ctrl = StreamController<ItemConOverlay?>();
    addTearDown(ctrl.close);
    // No se usa pumpAndSettle con el stream vacío: el estado de carga muestra un spinner
    // que nunca settlea. Se monta, se emite el 1er valor y recién ahí se settlea (ya es data).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemDetalleProvider('item-1').overrideWith((ref) => ctrl.stream),
        ],
        child: const MaterialApp(home: DetalleItemScreen(itemId: 'item-1')),
      ),
    );

    // 1) Con conflicto: el aviso aparece.
    ctrl.add(_item(
      estadoServidor: 'abierto',
      estadoMostrado: 'abierto',
      estadoEnConflicto: 'en_progreso',
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('En revisión por el Coordinador'), findsOneWidget);

    // 2) El reconciliador cerró la fila (descartado/sincronizado) → sin intención en
    //    conflicto → el aviso desaparece.
    ctrl.add(_item(estadoServidor: 'abierto', estadoMostrado: 'abierto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('En revisión por el Coordinador'), findsNothing);
  });
}
