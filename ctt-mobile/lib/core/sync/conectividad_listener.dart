/// conectividad_listener.dart — Flush inmediato de la cola al recuperar señal.
///
/// Al detectar la transición offline → online:
///   1. Ejecuta el flush foreground (cicloSyncProvider) usando las instancias
///      del ProviderScope — sin crear una nueva BaseDatosCTT.
///   2. Si el flush completa sin excepción: NO registra el WorkManager one-off.
///      La cola ya está vacía; no hay riesgo de dos BaseDatosCTT simultáneas.
///   3. Si el flush lanza excepción: registra el one-off como red de seguridad.
///
/// El WorkManager periódico (15 min) cubre el caso en que la app esté en background.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:workmanager/workmanager.dart';

import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/sync_service.dart';

part 'conectividad_listener.g.dart';

@Riverpod(keepAlive: true)
class ConectividadListener extends _$ConectividadListener {
  @override
  void build() {
    var teniaRed = false;

    final sub = Connectivity().onConnectivityChanged.listen((resultados) async {
      final tieneRed = resultados.any((r) => r != ConnectivityResult.none);
      final flancoAOnline = tieneRed && !teniaRed;
      // Actualizar el flanco ANTES del await: Stream.listen con callback async no
      // espera a que termine el callback anterior. Si `teniaRed` se asignara
      // después del await, un segundo evento de conectividad entraría con el valor
      // viejo y dispararía un flush concurrente sobre la misma cola (CTT-105).
      teniaRed = tieneRed;

      if (flancoAOnline) {
        try {
          // Flush foreground: usa BD y Dio del ProviderScope. Sin instancias nuevas.
          await ref.read(cicloSyncProvider).ejecutar();
          // Flush completó — cola vacía. No registrar one-off: evitar dos
          // BaseDatosCTT sobre el mismo .db si WorkManager despertara de inmediato.
        } catch (_) {
          // Flush falló (red inestable, error inesperado): WorkManager reintenta.
          await Workmanager().registerOneOffTask(
            kTaskFlushName,
            kTaskNameSync,
            existingWorkPolicy: ExistingWorkPolicy.replace,
            constraints: Constraints(networkType: NetworkType.connected),
          );
        }
      }
    });

    ref.onDispose(sub.cancel);
  }
}
