/// router_cargando_test.dart — CTT-138 commit 9.
///
/// Mientras estadoAuth == cargando, el router muestra PantallaCarga, NO /login
/// (evita el flash de login en el arranque offline). Control: sinSesion → login.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/app.dart';
import 'package:ctt_mobile/core/sync/conectividad_listener.dart';
import 'package:ctt_mobile/presentation/auth/login_screen.dart';
import 'package:ctt_mobile/presentation/auth/perfil_notifier.dart';

/// Perfil falso para que el router NO dispare /me (sin Firebase/Dio en el test).
class _FakePerfil extends PerfilSesion {
  @override
  Future<ResultadoSesion> build() async => const ResultadoSesion.sinSesion();
}

Widget _app(EstadoAuth estado) => ProviderScope(
      overrides: [
        estadoAuthProvider.overrideWithValue(estado),
        perfilSesionProvider.overrideWith(_FakePerfil.new),
        hayConexionProvider.overrideWith((ref) async => true),
      ],
      child: Consumer(
        builder: (context, ref, _) =>
            MaterialApp.router(routerConfig: ref.watch(routerProvider)),
      ),
    );

void main() {
  testWidgets('estadoAuth cargando → PantallaCarga, NO LoginScreen', (tester) async {
    await tester.pumpWidget(_app(EstadoAuth.cargando));
    await tester.pump(); // resuelve el redirect inicial
    await tester.pump(const Duration(milliseconds: 50));

    // No usar pumpAndSettle: el CircularProgressIndicator anima para siempre.
    expect(find.byType(PantallaCarga), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('estadoAuth sinSesion → LoginScreen (control)', (tester) async {
    await tester.pumpWidget(_app(EstadoAuth.sinSesion));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(PantallaCarga), findsNothing);
  });
}
