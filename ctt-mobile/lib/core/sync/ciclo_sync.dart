/// ciclo_sync.dart — Lógica del ciclo de sincronización con dependencias inyectadas.
///
/// [CicloSync] recibe sus dependencias por constructor y no instancia nada propio.
/// Se ejecuta desde dos caminos: WorkManager (headless, sync_service.dart) y
/// foreground (ProviderScope vía [cicloSyncProvider]).
///
/// La CLASIFICACIÓN de la respuesta HTTP (qué señal de dominio ocurrió + metadata)
/// es el único lugar que toca Dio; la DECISIÓN de a qué estado va la entrada la toma
/// la función pura [decidir]; el EFECTO lo aplica el DAO. El backoff (jitter +
/// Retry-After) se calcula acá porque necesita reloj y Random, no en la función pura.
library;

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import 'package:ctt_mobile/core/config/environment.dart';
import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/core/sync/reconciliador_conflictos.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'ciclo_sync.g.dart';

/// Reloj por defecto del ciclo (UTC). Top-level para poder ser default.
DateTime _ahoraUtcPorDefecto() => DateTime.now().toUtc();

/// Estado "sesión vencida" expuesto SOLO en foreground (CTT-103): el ciclo foreground
/// lo marca cuando un 401 pausa la cola; la UI lo lee para avisar. El headless no lo
/// toca (no hay UI). Lo limpia el flujo de re-login.
@riverpod
class SesionVencida extends _$SesionVencida {
  @override
  bool build() => false;
  void marcar() => state = true;
  void limpiar() => state = false;
}

/// Provider foreground: usa las instancias del ProviderScope. El ConectividadListener
/// lo lee para el flush inmediato al reconectar.
@riverpod
CicloSync cicloSync(CicloSyncRef ref) => CicloSync(
      syncDao: ref.watch(syncDaoProvider),
      dio: ref.watch(dioSyncProvider), // Dio de sync (sin 401→logout, con X-Sync-Origen)
      deviceIdService: ref.watch(deviceIdServiceProvider),
      isolateLabel: 'ui',
      // 401 en foreground → marca "sesión vencida" (no desloguea desde el sync).
      alSesionVencida: () => ref.read(sesionVencidaProvider.notifier).marcar(),
    );

/// Ciclo de sincronización reutilizable. No crea instancias propias.
class CicloSync {
  CicloSync({
    required this.syncDao,
    required this.dio,
    required this.deviceIdService,
    required this.isolateLabel,
    this.reloj = _ahoraUtcPorDefecto,
    this.alSesionVencida,
    Random? random,
  }) : random = random ?? Random();

  final SyncDao syncDao;
  final Dio dio;
  final DeviceIdService deviceIdService;

  /// Etiqueta del isolate ('ui' o 'headless'), parte del `tomado_por` del lease.
  final String isolateLabel;

  /// Reloj inyectable (UTC). Default: reloj del sistema.
  final DateTime Function() reloj;

  /// Callback de 401 (sesión vencida). Foreground lo cablea a [SesionVencida];
  /// headless lo deja null (no hay UI que avisar).
  final void Function()? alSesionVencida;

  /// Random para el full jitter del backoff. Inyectable para tests deterministas.
  final Random random;

  static const _margenLease = Duration(seconds: 30);

  /// Tope de pasadas por corrida (defensa anti-bucle). El criterio real de corte es
  /// el conjunto `intentados`: una fila nunca se intenta dos veces en la misma corrida,
  /// así que el while termina cuando no quedan filas reclamables sin intentar. El tope
  /// solo acota un caso patológico; si se alcanza, se deja un log de advertencia.
  static const kMaxPasadasPorCorrida = 50;

  /// Duración del lease (I4): cota superior de un envío (conexión + recepción del Dio
  /// de sync) + margen. 30s + 30s + 30s = 90s.
  static Duration get duracionLease =>
      Entorno.timeoutConexion + Entorno.timeoutRecepcion + _margenLease;

  /// Parámetros del backoff exponencial con full jitter (CTT-103).
  static const _backoffBase = Duration(seconds: 30);
  static const _backoffTope = Duration(minutes: 30);

  /// Lee la cola, envía cada cambio (push) y reconcilia los conflictos resueltos
  /// server-side (pull, CTT-117 tramo 3).
  Future<void> ejecutar() async {
    final instalacion = await deviceIdService.obtener();
    // tomado_por = instalación + isolate + corrida (UUID por ejecución): identidad del
    // lease para el claim y el cierre condicional (A2).
    final tomadoPor = '$instalacion:$isolateLabel:${const Uuid().v4()}';

    // Una fila nunca se intenta dos veces en la MISMA corrida (evita reprocesar una que
    // quedó pendiente con backoff). El while re-consulta filasReclamables porque cada
    // pasada cierra a terminal las primeras de cada agregado y DESBLOQUEA las siguientes
    // (FIFO por agregado): así se envía toda la cola elegible en una sola corrida, no
    // una fila por agregado. El tope de pasadas es solo defensa anti-bucle.
    final intentados = <String>{};
    var pausar = false;
    var pasada = 0;
    for (; pasada < kMaxPasadasPorCorrida && !pausar; pasada++) {
      final lote = (await syncDao.filasReclamables(reloj()))
          .where((f) => !intentados.contains(f.id))
          .toList();
      if (lote.isEmpty) break;

      for (final cambio in lote) {
        intentados.add(cambio.id);
        // Reloj y lease POR FILA (L1): cada fila se reclama con su instante real.
        final ahora = reloj();
        final tomadoHasta = ahora.add(duracionLease);
        final tomado = await syncDao.reclamar(
          cambio.id,
          tomadoPor: tomadoPor,
          ahora: ahora,
          tomadoHasta: tomadoHasta,
        );
        if (!tomado) continue;

        _Clasificacion clas;
        try {
          await _enviarCambio(
            accion: cambio.accion,
            entidadId: cambio.entidadId,
            payload: cambio.payload,
            idempotencyKey: cambio.idempotencyKey,
          );
          clas = _clas(SenalSync.envioOk);
        } catch (e) {
          clas = _clasificar(e);
        }
        // Instante DESPUÉS de la respuesta/excepción (mismo criterio que el Retry-After):
        // es el que se persiste en ultimo_intento_en y sincronizado_en.
        final finIntento = reloj();

        final decision = decidir(
          estadoActual: EstadoSyncLocal.enviando,
          senal: clas.senal,
        );

        // D5: al alcanzar el tope de intentos_servidor, derivar la fila a /sync/rescate
        // → en_revision (la revisa el coordinador, CTT-134). Si el rescate falla (p. ej.
        // 403 por cuenta inactiva), la fila cae al camino normal: sigue pendiente con
        // backoff y reintenta el rescate en una corrida futura — NUNCA se descarta.
        if (decision.incremento == IncrementoContador.servidor &&
            cambio.intentosServidor + 1 >= kTopeIntentosServidor &&
            await _rescatarFila(cambio, instalacion, clas)) {
          await syncDao.aplicarDecision(
            cambio.id,
            estadoEsperado: EstadoSyncLocal.enviando,
            decision: const DecisionSync(
              nuevoEstado: EstadoSyncLocal.enRevision,
              motivo: MotivoSync.fallaServidor,
            ),
            tomadoPor: tomadoPor,
            extra: SyncPendientesCompanion(
              intentosServidor: Value(cambio.intentosServidor + 1),
              ultimoError: clas.detalle != null
                  ? Value(clas.detalle)
                  : const Value.absent(),
              ultimoErrorCodigo: Value(clas.codigo),
              ultimoIntentoEn: Value(finIntento),
            ),
          );
          continue;
        }

        final extra = _efectos(cambio, decision, clas, ahora, finIntento);

        // Cierre condicional (A2): si esta corrida perdió el lease, es un no-op logueado.
        await syncDao.aplicarDecision(
          cambio.id,
          estadoEsperado: EstadoSyncLocal.enviando,
          decision: decision,
          tomadoPor: tomadoPor,
          extra: extra,
        );

        if (decision.pausaCola) {
          // 401: avisar (solo foreground) y ABORTAR la corrida — no seguir con las demás.
          alSesionVencida?.call();
          pausar = true;
          break;
        }
      }
    }
    if (pasada >= kMaxPasadasPorCorrida) {
      debugPrint(
        'CTT-103: ejecutar() alcanzó el tope de $kMaxPasadasPorCorrida pasadas; '
        'pueden quedar filas reclamables sin intentar en esta corrida.',
      );
    }

    // ── Pull (CTT-117 tramo 3): cerrar conflictos ya resueltos. Best-effort. ──
    try {
      await ReconciliadorConflictos(syncDao: syncDao, dio: dio)
          .reconciliarSiCorresponde();
    } catch (_) {
      // El periódico y los demás disparadores reintentan.
    }
  }

  /// Campos EXTRA a escribir según la decisión y la metadata del transporte:
  /// contadores + backoff, conflicto_id/rechazo_id y ultimo_error/código.
  SyncPendientesCompanion _efectos(
    SyncPendiente cambio,
    DecisionSync decision,
    _Clasificacion clas,
    DateTime ahora,
    DateTime finIntento,
  ) {
    var extra = const SyncPendientesCompanion();

    switch (decision.incremento) {
      case IncrementoContador.red:
        final n = cambio.intentosRed + 1;
        extra = extra.copyWith(
          intentosRed: Value(n),
          proximoIntentoEn: decision.aplicaBackoff
              ? Value(ahora.add(_backoff(n, clas.retryAfter)))
              : const Value.absent(),
        );
      case IncrementoContador.servidor:
        final n = cambio.intentosServidor + 1;
        extra = extra.copyWith(
          intentosServidor: Value(n),
          proximoIntentoEn: decision.aplicaBackoff
              ? Value(ahora.add(_backoff(n, clas.retryAfter)))
              : const Value.absent(),
        );
        // Al tope de intentos_servidor, ejecutar() ya intentó derivar a /sync/rescate
        // (D5) ANTES de llegar acá; _efectos solo corre si no se alcanzó el tope o si
        // el rescate falló → la fila sigue pendiente con este backoff (nunca descarta).
      case IncrementoContador.ninguno:
        break;
    }

    if (clas.conflictoId != null) {
      extra = extra.copyWith(conflictoId: Value(clas.conflictoId));
    }
    if (clas.rechazoId != null) {
      extra = extra.copyWith(rechazoId: Value(clas.rechazoId));
    }
    if (clas.detalle != null) {
      extra = extra.copyWith(ultimoError: Value(clas.detalle));
    }
    // SIEMPRE se escribe ultimo_error_codigo, incluido null en una falla sin respuesta
    // (red/timeout). Si arrastrara el código de un intento anterior, liberarBackoffRed
    // no reconocería la última falla como de red y no soltaría el backoff (L3).
    extra = extra.copyWith(ultimoErrorCodigo: Value(clas.codigo));
    // 401: limpiar el backoff para reintentar apenas vuelva la sesión.
    if (decision.pausaCola) {
      extra = extra.copyWith(proximoIntentoEn: const Value(null));
    }
    // Siempre hubo un intento: registrar su instante (post-respuesta). Y si la fila
    // llegó a sincronizado, sellar sincronizado_en con el mismo instante.
    extra = extra.copyWith(ultimoIntentoEn: Value(finIntento));
    if (decision.nuevoEstado == EstadoSyncLocal.sincronizado) {
      extra = extra.copyWith(sincronizadoEn: Value(finIntento));
    }
    return extra;
  }

  /// Backoff exponencial con FULL JITTER (CTT-103): espera uniforme en [0, min(30s·2^n,
  /// 30min)]; `Retry-After` (429/503), si viene, es el PISO.
  Duration _backoff(int n, Duration? retryAfter) {
    final nCap = n > 16 ? 16 : n; // evita overflow de 1<<n (el tope de 30min ya acota)
    final candidato = _backoffBase * (1 << nCap);
    final cap = candidato > _backoffTope ? _backoffTope : candidato;
    var espera =
        Duration(milliseconds: (random.nextDouble() * cap.inMilliseconds).round());
    if (retryAfter != null && retryAfter > espera) espera = retryAfter;
    return espera;
  }

  /// Traduce la excepción de envío a una [SenalSync] de dominio + la metadata a
  /// persistir. Único método acoplado a Dio.
  _Clasificacion _clasificar(Object error) {
    if (error is! DioException) {
      // No-Dio (p. ej. el stub de subir_foto): transitorio — NUNCA descarta.
      return _clas(SenalSync.fallaTransitoriaRed);
    }
    final status = error.response?.statusCode;
    final detalle = extraerDetalleBackend(error);
    final retryAfter = extraerRetryAfter(error);

    // Sin respuesta (red/timeout) → transitorio de red.
    if (status == null) {
      return _clas(SenalSync.fallaTransitoriaRed, detalle: detalle);
    }
    // 401 → pausa (no toca contadores).
    if (status == 401) {
      return _clas(SenalSync.sesionVencida, codigo: 401);
    }
    // Cualquier 4xx con rechazo_id → rechazada (terminal); guarda rechazo_id + motivo.
    final rechazoId = extraerRechazoId(error);
    if (status >= 400 && status < 500 && rechazoId != null) {
      final motivoSrv = extraerMotivoRechazo(error);
      final msg = motivoSrv != null ? '$motivoSrv: $detalle' : detalle;
      return _clas(SenalSync.rechazadoPorServidor,
          rechazoId: rechazoId, detalle: msg, codigo: status,);
    }
    if (status == 409) {
      final cid = extraerConflictoId(error);
      if (cid != null) {
        return _clas(SenalSync.conflictoDetectado, conflictoId: cid, codigo: 409);
      }
      // solicitud_en_proceso (A1) u otro 409 sin conflicto_id → intentos_servidor.
      return _clas(SenalSync.fallaServidor,
          detalle: detalle, codigo: 409, retryAfter: retryAfter,);
    }
    // Transitorio de servidor (fuente única): 5xx salvo 501, 408, 429.
    if (esStatusTransitorioServidor(status)) {
      return _clas(SenalSync.fallaTransitoriaRed,
          detalle: detalle, codigo: status, retryAfter: retryAfter,);
    }
    // Resto de 4xx sin rechazo_id (422, 403/404 de sesión, 501, desconocidos) →
    // intentos_servidor.
    return _clas(SenalSync.fallaServidor,
        detalle: detalle, codigo: status, retryAfter: retryAfter,);
  }

  _Clasificacion _clas(
    SenalSync senal, {
    String? conflictoId,
    String? rechazoId,
    String? detalle,
    int? codigo,
    Duration? retryAfter,
  }) =>
      (
        senal: senal,
        conflictoId: conflictoId,
        rechazoId: rechazoId,
        detalle: detalle,
        codigo: codigo,
        retryAfter: retryAfter,
      );

  /// Deriva una fila al servidor de rescate (/sync/rescate) — CTT-103 D5. Envía la fila
  /// COMPLETA (mismo formato que el flujo de pantalla, vía filaCrudaParaRescate),
  /// sobrescribiendo los campos de la falla ACTUAL ([clas]) para que la cuarentena
  /// registre por qué se escaló: intentos_servidor (+1), ultimo_error y
  /// ultimo_error_codigo. Devuelve true SOLO si el servidor la aceptó en cuarentena;
  /// false ante 403 / 5xx / 4xx / red o rechazo por tenant → la fila sigue pendiente.
  /// Usa el Dio de sync (ya autenticado por su AuthInterceptor).
  Future<bool> _rescatarFila(
    SyncPendiente f,
    String instalacion,
    _Clasificacion clas,
  ) async {
    final fila = await syncDao.filaCrudaParaRescate(f.id);
    if (fila == null) return false; // desapareció entre el claim y el rescate
    // Valores de la falla actual (la 6ª): la fila en la BD todavía tiene los previos.
    fila['intentos_servidor'] = f.intentosServidor + 1;
    fila['ultimo_error'] = clas.detalle;
    fila['ultimo_error_codigo'] = clas.codigo;
    try {
      final resp = await dio.post<Map<String, dynamic>>(
        '/sync/rescate',
        data: {'instalacion_id': instalacion, 'filas': [fila]},
      );
      final data = resp.data ?? const {};
      final aceptada = (((data['aceptadas'] as int?) ?? 0) +
              ((data['ya_aplicadas'] as int?) ?? 0) +
              ((data['duplicadas'] as int?) ?? 0)) >=
          1;
      final rechazadaTenant = ((data['rechazadas_tenant'] as int?) ?? 0) >= 1;
      return aceptada && !rechazadaTenant;
    } on DioException {
      return false; // la fila sigue pendiente; se reintenta el rescate más tarde.
    }
  }

  Future<void> _enviarCambio({
    required String accion,
    required String entidadId,
    required String payload,
    String? idempotencyKey,
  }) async {
    final data = jsonDecode(payload) as Map<String, dynamic>;

    switch (accion) {
      case 'cambio_estado_item':
        // La clave va como header, NO en el payload (alimenta el fingerprint del
        // servidor; meterla ahí rompería la deduplicación — CTT-105).
        await dio.post<void>(
          '/items/$entidadId/transicion',
          data: data,
          options: idempotencyKey != null
              ? Options(headers: {'Idempotency-Key': idempotencyKey})
              : null,
        );
      case 'subir_foto':
        // Stub deliberado (CTT-99): throw → falla transitoria, nunca éxito sin 2xx.
        throw UnimplementedError(
          'subir_foto: la captura y subida de evidencia no está implementada (CTT-99).',
        );
      default:
        throw Exception('Acción de sync desconocida: $accion');
    }
  }
}

/// Resultado de [CicloSync._clasificar]: señal de dominio + metadata de transporte.
typedef _Clasificacion = ({
  SenalSync senal,
  String? conflictoId,
  String? rechazoId,
  String? detalle,
  int? codigo,
  Duration? retryAfter,
});
