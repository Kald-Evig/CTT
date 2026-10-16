/// mis_items_banner_offline_test.dart — CTT-138 commit 10.
///
/// La lista del Trabajador (donde aterriza en el arranque en frío sin red) muestra el
/// BannerOffline "Sin conexión · verificado hace X" cuando la sesión es offline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/presentation/auth/ventana_offline.dart';
import 'package:ctt_mobile/presentation/shared/item_detalle_widgets.dart'
    show BannerOffline;
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_screen.dart';

Widget _app(EstadoVentanaOffline estado) => ProviderScope(
      overrides: [
        misItemsProvider.overrideWith((ref) => Stream.value(<ItemsCacheTableData>[])),
        estadoVentanaOfflineProvider.overrideWith((ref) async => estado),
      ],
      child: const MaterialApp(home: MisItemsScreen()),
    );

void main() {
  testWidgets('offline → BannerOffline con "verificado hace X" en la lista',
      (tester) async {
    await tester.pumpWidget(_app(const EstadoVentanaOffline(
      esOffline: true,
      verificadoHace: Duration(hours: 3),
    )));
    await tester.pumpAndSettle();

    expect(find.byType(BannerOffline), findsOneWidget);
    expect(
      find.textContaining('Sin conexión · verificado hace 3 h'),
      findsOneWidget,
    );
  });

  testWidgets('online → sin el texto del banner', (tester) async {
    await tester.pumpWidget(_app(const EstadoVentanaOffline(esOffline: false)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sin conexión ·'), findsNothing);
  });
}
