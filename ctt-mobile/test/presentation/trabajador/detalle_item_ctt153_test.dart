/// detalle_item_ctt153_test.dart — CTT-153: la pantalla del Trabajador no ofrece
/// transiciones en problema; textos literales de problema y pendiente_revision.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/data/local/daos/items_cache_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/presentation/trabajador/detalle_item_screen.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';

ItemConOverlay _item(String estado) => ItemConOverlay(
      base: ItemsCacheTableData(
        id: 'item-1',
        proyectoId: 'p1',
        proyectoNombre: 'Proyecto X',
        nivelProfundidad: 0,
        nombre: 'Tarea de prueba',
        estadoServidor: estado,
        tieneConflicto: false,
        cachadoEn: DateTime.utc(2026, 1, 1),
      ),
      estadoMostrado: estado,
    );

Future<void> _pump(WidgetTester tester, String estado) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        itemDetalleProvider('item-1')
            .overrideWith((ref) => Stream.value(_item(estado))),
      ],
      child: const MaterialApp(home: DetalleItemScreen(itemId: 'item-1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('problema: ningún botón de transición + texto literal', (tester) async {
    await _pump(tester, 'problema');

    expect(
      find.text('Problema reportado. Esperando que el Residente lo cierre.'),
      findsOneWidget,
    );
    // Ninguna transición ofrecida (en especial, ya no "Reanudar trabajo").
    for (final boton in [
      'Reanudar trabajo',
      'Iniciar trabajo',
      'Marcar como terminado',
      'Reportar problema',
    ]) {
      expect(find.text(boton), findsNothing, reason: 'no debe verse "$boton"');
    }
  });

  testWidgets('pendiente_revision: texto literal de esa sección', (tester) async {
    await _pump(tester, 'pendiente_revision');

    expect(
      find.text('Ítem enviado a revisión. Esperando aprobación.'),
      findsOneWidget,
    );
    for (final boton in ['Marcar como terminado', 'Reportar problema']) {
      expect(find.text(boton), findsNothing);
    }
  });
}
