/// main.dart — Punto de entrada de la app CTT.
///
/// Orden de inicialización:
///   1. WidgetsFlutterBinding
///   2. Firebase (Crashlytics siempre, Analytics solo en release)
///   3. WorkManager / SyncService
///   4. ProviderScope (Riverpod)
///
/// Crashlytics captura todos los errores no controlados.
/// NUNCA loggear tokens, RUT ni datos personales en los reportes.
library;

import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:ctt_mobile/core/config/environment.dart';
import 'package:ctt_mobile/core/security/defensa_sesion_io.dart';
import 'package:ctt_mobile/core/sync/sync_service.dart';
import 'package:ctt_mobile/firebase_options.dart';
import 'package:ctt_mobile/app.dart';

Future<void> main() async {
  // Garantiza que los bindings estén listos antes de cualquier await.
  WidgetsFlutterBinding.ensureInitialized();

  // CTT-147 fase 2 (sanar): ANTES de inicializar Firebase, y solo en el isolate de UI (main);
  // el headless de WorkManager no pasa por acá. Nunca impide el arranque.
  await _sanarSesionFirebaseSiCorresponde();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  _configurarCrashlytics();

  await inicializarSyncService();

  runApp(
    const ProviderScope(
      child: AppCTT(),
    ),
  );
}

/// CTT-147 fase 2: si la fase 1 dejó la marca "sanar", borra los XML de Firebase Auth antes de
/// `Firebase.initializeApp`, para que Firebase arranque limpio (recrea sus archivos recién en el
/// primer login — ctt147_exp ii). Crashlytics aún no está disponible acá: se registra con
/// debugPrint. Cualquier error se traga (la defensa nunca impide el arranque; la marca queda
/// para reintentar).
Future<void> _sanarSesionFirebaseSiCorresponde() async {
  try {
    final io = await crearDefensaSesionIo();
    final borrados = io.defensa.sanarFase2(
      io.archivos,
      alError: (e, st) => debugPrint('[CTT-147] fase 2 error: $e'),
    );
    if (borrados > 0) {
      debugPrint('[CTT-147] fase 2: $borrados archivo(s) de Firebase Auth borrados');
    }
  } catch (e, _) {
    debugPrint('[CTT-147] fase 2 no ejecutada: $e');
  }
}

void _configurarCrashlytics() {
  final crashlytics = FirebaseCrashlytics.instance;

  // Captura errores del framework Flutter (widgets, layouts, rendering).
  FlutterError.onError = crashlytics.recordFlutterFatalError;

  // Captura errores Dart asíncronos fuera del árbol de widgets.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };

  // En debug/profile solo colectar, no enviar a Firebase para no contaminar métricas.
  crashlytics.setCrashlyticsCollectionEnabled(Entorno.esRelease);
}
