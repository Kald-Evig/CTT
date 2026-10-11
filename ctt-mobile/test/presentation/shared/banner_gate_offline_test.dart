/// banner_gate_offline_test.dart — CTT-138 commit 4.
///
/// BannerOffline muestra "Sin conexión · verificado hace X" cuando la sesión es
/// offline; GateCapturaOffline bloquea las acciones (muestra "Conéctate para seguir")
/// cuando la ventana venció, y las muestra si no.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/presentation/auth/ventana_offline.dart';
import 'package:ctt_mobile/presentation/shared/item_detalle_widgets.dart';

Widget _app(Widget child, EstadoVentanaOffline estado) => ProviderScope(
      overrides: [
        estadoVentanaOfflineProvider.overrideWith((ref) async => estado),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('banner muestra "verificado hace X" cuando offline', (tester) async {
    await tester.pumpWidget(_app(
      const BannerOffline(),
      const EstadoVentanaOffline(
          esOffline: true, verificadoHace: Duration(hours: 2)),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sin conexión · verificado hace 2 h'),
        findsOneWidget);
  });

  testWidgets('banner vacío cuando online', (tester) async {
    await tester.pumpWidget(_app(
      const BannerOffline(),
      const EstadoVentanaOffline(esOffline: false),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sin conexión'), findsNothing);
  });

  testWidgets('gate bloquea las acciones cuando la ventana venció', (tester) async {
    await tester.pumpWidget(_app(
      const GateCapturaOffline(acciones: Text('ACCION')),
      const EstadoVentanaOffline(esOffline: true, vencida: true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ACCION'), findsNothing);
    expect(find.textContaining('Conéctate para seguir'), findsOneWidget);
  });

  testWidgets('gate muestra las acciones cuando no venció', (tester) async {
    await tester.pumpWidget(_app(
      const GateCapturaOffline(acciones: Text('ACCION')),
      const EstadoVentanaOffline(esOffline: true, vencida: false),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ACCION'), findsOneWidget);
    expect(find.textContaining('Conéctate para seguir'), findsNothing);
  });
}
