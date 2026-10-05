/// mis_items_badge_sync_test.dart — CTT-103 D6.
///
/// El indicador de sync en mis_items: chip "Envío rechazado — lo revisa coordinación"
/// para rechazada y "Envío en revisión por coordinación" para en_revision. Prioridad:
/// nube naranja (pendiente/enviando/esperando) > rechazada > en_revision.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_screen.dart';

ItemsCacheTableData _item(String id, String estado) => ItemsCacheTableData(
      id: id,
      proyectoId: 'p1',
      proyectoNombre: 'Obra',
      nivelProfundidad: 0,
      nombre: 'Ítem $id',
      estado: estado,
      tieneConflicto: false,
      updatedAt: DateTime.utc(2026, 1, 1),
      cachadoEn: DateTime.utc(2026, 1, 1),
    );

const _txtRechazada = 'Envío rechazado — lo revisa coordinación';
const _txtEnRevision = 'Envío en revisión por coordinación';

void main() {
  testWidgets('badge por estado de sync, con prioridad nube > rechazada > en_revision',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          misItemsProvider.overrideWith((ref) async => [
                _item('p', 'en_progreso'), // pendiente → nube
                _item('r', 'pendiente_revision'), // rechazada → chip
                _item('v', 'abierto'), // en_revision → chip
                _item('dos', 'terminado'), // pendiente Y rechazada → gana la nube
              ]),
          // pendiente/enviando/esperando: 'p' y 'dos'.
          itemsConSyncPendienteProvider.overrideWith((ref) async => {'p', 'dos'}),
          // rechazada/en_revision: 'r', 'v' y 'dos' (dos también, para probar prioridad).
          itemsEnRevisionProvider.overrideWith((ref) async => {
                'r': EstadoSyncLocal.rechazada,
                'v': EstadoSyncLocal.enRevision,
                'dos': EstadoSyncLocal.rechazada,
              }),
        ],
        child: const MaterialApp(home: MisItemsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 'r' muestra el chip de rechazada; 'v' el de en_revision. 'dos' NO muestra chip
    // (gana la nube de pendiente), así que cada texto aparece EXACTAMENTE una vez.
    expect(find.text(_txtRechazada), findsOneWidget);
    expect(find.text(_txtEnRevision), findsOneWidget);

    // Nube naranja en 'p' y 'dos' (los pendientes): 2 íconos.
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNWidgets(2));
  });
}
