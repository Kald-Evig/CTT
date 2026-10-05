/// reconciliador_conflictos.dart — Cierre local de conflictos resueltos (CTT-117 tramo 3).
///
/// Es el CONSUMIDOR de `GET /sync/conflictos/mios` que faltaba: saca a las filas
/// de `esperandoResolucion` de su sumidero. Casa cada fila parqueada contra los
/// conflictos RESUELTOS del usuario (por `conflictoId`), traduce el resultado a una
/// [SenalSync] de dominio y llama a la función pura [decidir] — nunca reimplementa
/// la máquina de estados. Al llegar a terminal, apaga el flag de conflicto del ítem.
///
/// Igual que ciclo_sync y transicion_service, este es un LLAMADOR de [decidir]: la
/// clasificación (fila de /mios → señal) vive acá; la decisión, en decision_sync.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'reconciliador_conflictos.g.dart';

/// Provider foreground: usa el Dio autenticado y el DAO del ProviderScope.
/// El isolate headless de WorkManager arma el suyo a mano (sync_service.dart).
@riverpod
ReconciliadorConflictos reconciliadorConflictos(ReconciliadorConflictosRef ref) =>
    ReconciliadorConflictos(
      syncDao: ref.watch(syncDaoProvider),
      dio: ref.watch(dioClientProvider),
    );

class ReconciliadorConflictos {
  const ReconciliadorConflictos({
    required this.syncDao,
    required this.dio,
  });

  final SyncDao syncDao;
  final Dio dio;

  /// Ventana de debounce entre reconciliaciones efectivas. El intervalo mínimo de
  /// WorkManager es un piso, no una garantía, y hay cuatro disparadores (arranque,
  /// resumed, conectividad, periódico) que pueden solaparse; el debounce evita
  /// reconciliar en cada uno. Persistido en Drift (ver [SyncDao]).
  static const ventanaDebounce = Duration(minutes: 2);

  /// Reconcilia solo si pasó la [ventanaDebounce] desde la última corrida efectiva.
  /// El reloj se guarda en Drift para coordinar entre el isolate de UI y el
  /// headless de WorkManager. Una corrida VACÍA (sin filas parqueadas) no consume
  /// la ventana: [reconciliar] devuelve false y no se registra.
  Future<void> reconciliarSiCorresponde({DateTime? ahora}) async {
    final now = ahora ?? DateTime.now().toUtc();
    final ultima = await syncDao.ultimaReconciliacion();
    if (ultima != null && now.difference(ultima) < ventanaDebounce) return;
    final consulto = await reconciliar();
    if (consulto) await syncDao.registrarReconciliacion(now);
  }

  /// Cierra las filas locales en `esperandoResolucion` cuyo conflicto ya resolvió
  /// el servidor. Devuelve `true` si consultó el servidor (había filas parqueadas)
  /// y `false` si no había nada que reconciliar — el llamador usa ese dato para no
  /// gastar la ventana del debounce en corridas vacías.
  Future<bool> reconciliar() async {
    final enEspera = await syncDao.obtenerEnEsperaResolucion();
    if (enEspera.isEmpty) return false;

    // Mapa conflictoId → version_ganadora (String?), solo de conflictos RESUELTOS
    // del usuario del token. /mios NO devuelve pendientes (sync.py:111).
    final resueltos = await _conflictosResueltos();

    for (final fila in enEspera) {
      final cid = fila.conflictoId;
      if (cid == null) {
        // Invariante CTT-103 C4: ninguna fila entra a esperando_resolucion sin
        // conflicto_id (lo garantizan el ciclo y encolarEnConflicto). Si igual
        // apareciera una (fila corrupta/legacy), se loguea y se DEJA — nunca se
        // descarta en el dispositivo. Ya no existe la rama heredado_indeterminado.
        debugPrint(
          'CTT-103: fila ${fila.id} en esperando_resolucion sin conflicto_id; se '
          'ignora (no debería ocurrir — invariante C4).',
        );
        continue;
      }
      if (!resueltos.containsKey(cid)) {
        // conflictoId presente pero NO en /mios: sigue PENDIENTE server-side (/mios
        // solo trae resueltos). No se descarta — se reintenta en una corrida futura.
        continue;
      }
      final SenalSync senal;
      switch (resueltos[cid]) {
        case 'local':
          senal = SenalSync.resolucionGanoCliente; // aplicó el cambio del cliente
        case 'servidor':
          senal = SenalSync.resolucionGanoServidor; // el ítem no se tocó
        default:
          // Resuelto pero sin version_ganadora (null): no se puede afirmar quién
          // ganó. NO se descarta; se reintenta cuando el server complete el dato.
          continue;
      }

      final decision = decidir(
        estadoActual: EstadoSyncLocal.esperandoResolucion,
        senal: senal,
      );
      // aplicarDecision cierra la fila Y apaga items_cache.tiene_conflicto en la
      // misma transacción (escritor único del flag, CTT-117 tramo 3).
      await syncDao.aplicarDecision(
        fila.id,
        estadoEsperado: EstadoSyncLocal.esperandoResolucion,
        decision: decision,
      );
    }
    return true;
  }

  /// GET /sync/conflictos/mios → {conflictoId: version_ganadora}. Se leen solo los
  /// dos campos necesarios para casar y decidir; el resto de ConflictoMioOut no se
  /// usa (el dispositivo ya tiene su cambio, solo necesita saber quién ganó).
  Future<Map<String, String?>> _conflictosResueltos() async {
    final resp = await dio.get<List<dynamic>>('/sync/conflictos/mios');
    final out = <String, String?>{};
    for (final item in resp.data ?? const []) {
      final m = item as Map<String, dynamic>;
      out[m['id'] as String] = m['version_ganadora'] as String?;
    }
    return out;
  }
}
