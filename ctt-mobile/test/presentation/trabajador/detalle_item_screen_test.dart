/// detalle_item_screen_test.dart — CTT-130 fase 3.
///
/// Ejerce el requisito: si al guardar un cambio se lanza
/// [SesionNoDisponibleException] (v6: la cola no admite filas sin dueño), el
/// trabajador ve un mensaje CLARO en pantalla — no un crash ni un fallo silencioso.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/sync/transicion_service.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/repositories/items_repository.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/trabajador/detalle_item_screen.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';

class _FakeItemsRepository extends Mock implements ItemsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(EstadoItem.enProgreso));

  ItemsCacheTableData itemEnProgreso() => ItemsCacheTableData(
        id: 'item-1',
        proyectoId: 'p1',
        proyectoNombre: 'Proyecto X',
        nivelProfundidad: 0,
        nombre: 'Tarea de prueba',
        estado: 'en_progreso',
        tieneConflicto: false,
        updatedAt: DateTime.utc(2026, 1, 1),
        cachadoEn: DateTime.utc(2026, 1, 1),
      );

  testWidgets(
      'SesionNoDisponibleException al guardar → SnackBar claro, no crash',
      (tester) async {
    final repo = _FakeItemsRepository();
    when(
      () => repo.cambiarEstado(
        itemId: any(named: 'itemId'),
        nuevoEstado: any(named: 'nuevoEstado'),
      ),
    ).thenThrow(const SesionNoDisponibleException('usuario_id/empresa_id nulos'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(repo),
          itemDetalleProvider('item-1').overrideWith((ref) => itemEnProgreso()),
        ],
        child: const MaterialApp(home: DetalleItemScreen(itemId: 'item-1')),
      ),
    );
    await tester.pumpAndSettle();

    // El trabajador toca "Marcar como terminado".
    await tester.tap(find.text('Marcar como terminado'));
    await tester.pumpAndSettle();

    // Ve un mensaje claro (no el toString de la excepción, no un crash).
    expect(
      find.textContaining('Tu sesión no está activa'),
      findsOneWidget,
    );
    expect(find.textContaining('SesionNoDisponibleException'), findsNothing);
  });
}
