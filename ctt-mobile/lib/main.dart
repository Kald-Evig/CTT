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
import 'package:ctt_mobile/core/sync/sync_service.dart';
import 'package:ctt_mobile/firebase_options.dart';
import 'package:ctt_mobile/app.dart';

Future<void> main() async {
  // Garantiza que los bindings estén listos antes de cualquier await.
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  _configurarCrashlytics();

  await inicializarSyncService();

  runApp(
    const ProviderScope(
      child: AppCTT(),
    ),
  );
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
