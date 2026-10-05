/// decision_sync_test.dart — CTT-103 (clasificador) / CTT-117 tramo 2.
///
/// Verifica la función de decisión pura y el GRAFO de transiciones: que ningún
/// estado no terminal sea un sumidero (candado anti-sumidero). Si alguien agrega un
/// estado no terminal sin darle salida, este test rompe.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

/// Intenta una transición; devuelve null si es una combinación inválida.
DecisionSync? _try(EstadoSyncLocal estado, SenalSync senal) {
  try {
    return decidir(estadoActual: estado, senal: senal);
  } on StateError {
    return null;
  }
}

void main() {
  final noTerminales =
      EstadoSyncLocal.values.where((e) => !e.esTerminal).toList();
  final terminales = EstadoSyncLocal.values.where((e) => e.esTerminal).toList();

  group('mapeo de señales (envío)', () {
    test('envioOk → sincronizado, SIN motivo (A4: no arrastra motivo previo)', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.envioOk,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.sincronizado);
      expect(d.motivo, isNull);
      expect(d.incremento, IncrementoContador.ninguno);
      expect(d.aplicaBackoff, isFalse);
    });

    test('conflictoDetectado → esperando_resolucion, motivo conflicto', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.conflictoDetectado,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.esperandoResolucion);
      expect(d.motivo, MotivoSync.conflicto);
    });

    test('rechazadoPorServidor → rechazada (terminal), motivo rechazoNegocio', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.rechazadoPorServidor,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.rechazada);
      expect(d.motivo, MotivoSync.rechazoNegocio);
      expect(d.incremento, IncrementoContador.ninguno);
    });

    test('fallaTransitoriaRed → pendiente, incrementa RED, backoff; NUNCA descarta',
        () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.fallaTransitoriaRed,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.pendiente);
      expect(d.motivo, MotivoSync.errorTransitorio);
      expect(d.incremento, IncrementoContador.red);
      expect(d.aplicaBackoff, isTrue);
    });

    test('fallaServidor → pendiente, incrementa SERVIDOR, backoff; NUNCA descarta',
        () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.fallaServidor,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.pendiente);
      expect(d.motivo, MotivoSync.fallaServidor);
      expect(d.incremento, IncrementoContador.servidor);
      expect(d.aplicaBackoff, isTrue);
    });

    test('sesionVencida (401) → pendiente, PAUSA, sin contadores ni backoff', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.sesionVencida,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.pendiente);
      expect(d.pausaCola, isTrue);
      expect(d.incremento, IncrementoContador.ninguno);
      expect(d.aplicaBackoff, isFalse);
    });
  });

  group('mapeo de señales (resolución, solo esperando_resolucion)', () {
    test('resolucionGanoCliente → sincronizado', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.esperandoResolucion,
        senal: SenalSync.resolucionGanoCliente,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.sincronizado);
      expect(d.motivo, MotivoSync.conflictoResueltoCliente);
    });

    test('resolucionGanoServidor → descartado', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.esperandoResolucion,
        senal: SenalSync.resolucionGanoServidor,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.descartado);
      expect(d.motivo, MotivoSync.conflictoResueltoServidor);
    });

    test('las señales de resolución son inválidas en enviando (solo espera)', () {
      expect(
        () => decidir(
          estadoActual: EstadoSyncLocal.enviando,
          senal: SenalSync.resolucionGanoCliente,
        ),
        throwsStateError,
      );
    });

    test('las señales de envío son inválidas en esperando_resolucion', () {
      for (final s in [
        SenalSync.envioOk,
        SenalSync.fallaTransitoriaRed,
        SenalSync.fallaServidor,
        SenalSync.rechazadoPorServidor,
        SenalSync.sesionVencida,
        SenalSync.conflictoDetectado,
      ]) {
        expect(() => _try(EstadoSyncLocal.esperandoResolucion, s), returnsNormally);
        expect(_try(EstadoSyncLocal.esperandoResolucion, s), isNull,
            reason: '$s no debería ser válida en esperando_resolucion',);
      }
    });
  });

  group('grafo de transiciones', () {
    test('los estados terminales no aceptan NINGUNA señal', () {
      for (final t in terminales) {
        for (final s in SenalSync.values) {
          expect(
            () => decidir(estadoActual: t, senal: s),
            throwsStateError,
            reason: '$t es terminal; no debería aceptar $s',
          );
        }
      }
    });

    test('TODO estado no terminal tiene al menos una salida a otro estado '
        '(candado anti-sumidero)', () {
      for (final estado in noTerminales) {
        final salidas = <EstadoSyncLocal>{};
        for (final s in SenalSync.values) {
          final d = _try(estado, s);
          if (d != null && d.nuevoEstado != estado) salidas.add(d.nuevoEstado);
        }
        expect(salidas, isNotEmpty,
            reason: '$estado es un sumidero: ninguna señal lo saca de sí mismo',);
      }
    });

    test('sincronizado, descartado y rechazada son alcanzables desde pendiente', () {
      // BFS sobre el grafo partiendo de pendiente, explorando toda señal. en_revision
      // NO lo produce decidir (lo setea el ciclo al derivar a rescate — CTT-103 D5).
      final visitados = <EstadoSyncLocal>{EstadoSyncLocal.pendiente};
      final cola = <EstadoSyncLocal>[EstadoSyncLocal.pendiente];
      while (cola.isNotEmpty) {
        final actual = cola.removeAt(0);
        if (actual.esTerminal) continue;
        for (final s in SenalSync.values) {
          final d = _try(actual, s);
          if (d != null && visitados.add(d.nuevoEstado)) cola.add(d.nuevoEstado);
        }
      }
      expect(visitados.contains(EstadoSyncLocal.sincronizado), isTrue);
      expect(visitados.contains(EstadoSyncLocal.descartado), isTrue);
      expect(visitados.contains(EstadoSyncLocal.rechazada), isTrue);
    });
  });

  // ── Candado del EMISOR (CTT-117 tramo 3) ───────────────────────────────────
  // esperando_resolucion es no terminal; su única salida son las señales de
  // resolución. El test del grafo verifica que decidir() tiene arista de salida, no
  // que un caller las EMITA. Este candado verifica el emisor real (el reconciliador).
  test('existe código de producción que emite las señales de resolución', () {
    final fuentes = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll(r'\', '/').endsWith(
            'lib/core/sync/decision_sync.dart',),);

    final emiteCliente = fuentes.any((f) =>
        f.readAsStringSync().contains('SenalSync.resolucionGanoCliente'),);
    final emiteServidor = fuentes.any((f) =>
        f.readAsStringSync().contains('SenalSync.resolucionGanoServidor'),);

    expect(emiteCliente && emiteServidor, isTrue,
        reason: 'Nadie emite las señales de resolución: esperando_resolucion '
            'volvería a ser un sumidero.',);
  });
}
