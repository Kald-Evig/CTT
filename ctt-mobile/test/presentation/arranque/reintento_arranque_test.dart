/// reintento_arranque_test.dart — CTT-130 fase 4 (V1).
///
/// El botón Reintentar tiene que servir DENTRO del mismo proceso: Drift cachea
/// _migrationError en la instancia y lo relanza en cada apertura (engines.dart).
/// Si el reintento reusara la misma instancia, no funcionaría hasta reiniciar la app.
/// Este test falla la primera apertura y la hace pasar en la segunda, sin reiniciar,
/// invalidando baseDatosCTTProvider (lo que hace el botón).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/presentation/arranque/arranque_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ctt_reintento');
    // path_provider: getApplicationDocumentsDirectory() → carpeta temporal.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // El handle de sqlite puede tardar en soltarse en Windows; irrelevante al test.
    }
  });

  test('V1 — reintento con instancia fresca: 1ra apertura falla, 2da pasa en el '
      'mismo proceso', () async {
    var intento = 0;

    final container = ProviderContainer(
      overrides: [
        // Simula lo que ve arranque: la 1ra vez, una base que revienta en la
        // primera query (como una migración fallida que Drift cachea y relanza);
        // la 2da, una base sana. arranque lee baseDatosCTTProvider, así que
        // invalidarlo entre intentos entrega una instancia distinta.
        baseDatosCTTProvider.overrideWith((ref) {
          intento++;
          if (intento == 1) {
            // 1ra apertura rota: como el _migrationError que Drift relanza en cada
            // apertura de la instancia dañada dentro del mismo proceso.
            throw StateError('migracion rota (instancia cacheada)');
          }
          return BaseDatosCTT.conConexion(NativeDatabase.memory());
        }),
      ],
    );
    addTearDown(container.dispose);

    // Primer arranque: falla.
    await expectLater(
      container.read(arranqueProvider.future),
      throwsA(anything),
    );

    // El botón Reintentar: instancia fresca + re-corre arranque.
    container.invalidate(baseDatosCTTProvider);
    container.invalidate(arranqueProvider);

    // Segundo arranque en el MISMO proceso: pasa.
    await expectLater(container.read(arranqueProvider.future), completes);
    expect(intento, 2); // se creó una instancia nueva, no se reusó la rota
  });
}
