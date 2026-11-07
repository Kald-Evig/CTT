/// ciclo_sync_ui.dart — Entrada ÚNICA al ciclo de sync del isolate 'ui' (CTT-141).
///
/// Envuelve [CicloSync.ejecutar] con single-flight + COALESCING: nunca se solapan dos
/// corridas de la UI, y las llamadas que llegan mientras hay una en vuelo se juntan en
/// UNA sola re-corrida que arranca apenas termina la actual. No descarta llamadas.
///
/// Invariante clave: el future que devuelve [ejecutar] se completa cuando termina una
/// corrida que EMPEZÓ DESPUÉS de esa llamada. `cerrarSesion` (auth_notifier) cuenta las
/// filas no terminales después de `await ejecutar()`; si se le devolviera la corrida en
/// vuelo —que pudo leer la cola ANTES de una fila recién encolada— contaría con datos
/// viejos. Por eso una llamada durante el vuelo espera la re-corrida, no la actual.
///
/// El mecanismo (single-flight + coalescing) vive en [GuardaCorridaUnica] y se COMPONE acá:
/// la UI solo usa la entrada run-after ([ejecutar]). La exclusión ENTRE isolates sigue siendo
/// el lease por fila (SyncDao.reclamar): el headless (sync_service.dart) NO pasa por este
/// guard, usa [CicloSync] directo.
///
/// Vive en un provider keepAlive porque [CicloSync] (cicloSyncProvider) es autoDispose y
/// se reconstruye entre lecturas: el estado del guard no puede vivir ahí.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/guarda_corrida_unica.dart';

part 'ciclo_sync_ui.g.dart';

/// Single-flight con una re-corrida pendiente (coalescing), delegado a [GuardaCorridaUnica].
/// Lógica pura: recibe la corrida real por constructor para poder testearse sin Riverpod ni Dio.
class CicloSyncUi {
  CicloSyncUi(Future<void> Function() correr) : _guarda = GuardaCorridaUnica(correr);

  final GuardaCorridaUnica _guarda;

  /// ¿Hay una corrida en vuelo? (para tests y para el guard del planificador).
  bool get enVuelo => _guarda.enVuelo;

  /// Ejecuta el ciclo con coalescing (run-after). Ver el invariante en el encabezado del archivo.
  Future<void> ejecutar() => _guarda.ejecutar();
}

/// Provider keepAlive: estado del guard estable toda la sesión. Cablea la corrida real al
/// ciclo foreground (cicloSyncProvider, autoDispose → se reconstruye en cada lectura, por
/// eso lee fresco en cada corrida). Los disparadores de la UI (conectividad, transición,
/// auth) y el planificador (CTT-141) llaman a ESTE, no a cicloSyncProvider.
@Riverpod(keepAlive: true)
CicloSyncUi cicloSyncUi(CicloSyncUiRef ref) =>
    CicloSyncUi(() => ref.read(cicloSyncProvider).ejecutar());
