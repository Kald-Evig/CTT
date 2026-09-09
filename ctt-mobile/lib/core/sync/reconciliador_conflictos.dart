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
      final SenalSync senal;

      if (cid != null && resueltos.containsKey(cid)) {
        // Resuelto server-side: el desenlace lo dicta version_ganadora.
        //   'local'    → aplicó el cambio del cliente (sync.py:150-168) → ganó cliente.
        //   'servidor' → el ítem no se tocó → ganó servidor.
        //   null       → resuelto antes de persistir la versión (rama indeterminada).
        senal = switch (resueltos[cid]) {
          'local' => SenalSync.resolucionGanoCliente,
          'servidor' => SenalSync.resolucionGanoServidor,
          _ => SenalSync.resolucionIndeterminada,
        };
      } else if (cid == null) {
        // Fila heredada por la migración sin conflicto_id casable: nunca podrá
        // corresponder con /mios. Terminal indeterminado.
        senal = SenalSync.resolucionIndeterminada;
      } else {
        // conflictoId presente pero NO en /mios: el conflicto sigue PENDIENTE
        // server-side (/mios solo trae resueltos). NO se descarta — se reintenta
        // en una corrida futura, cuando el Coordinador lo resuelva. La cola no
        // tiene dueño (no hay columna de usuario); en un dispositivo compartido
        // esta fila puede pertenecer a otro usuario. Ver CTT-123.
        continue;
      }

      final decision = decidir(
        estadoActual: EstadoSyncLocal.esperandoResolucion,
        senal: senal,
        reintentos: fila.reintentos,
      );
      // aplicarDecision cierra la fila Y apaga items_cache.tiene_conflicto en la
      // misma transacción (escritor único del flag, CTT-117 tramo 3).
      await syncDao.aplicarDecision(
        fila.id,
        estadoEsperado: EstadoSyncLocal.esperandoResolucion,
        decision: decision,
        reintentosActuales: fila.reintentos,
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
