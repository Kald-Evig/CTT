/// decision_sync_test.dart — CTT-117 tramo 2.
///
/// Verifica la función de decisión pura y, sobre todo, el GRAFO de transiciones:
/// que ningún estado no terminal sea un sumidero. Es el candado que impide que
/// el defecto de CTT-103 (una fila atrapada sin salida) reaparezca en un tercer
/// estado: si alguien agrega un estado no terminal sin darle salida, este test
/// rompe.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

/// Intenta una transición; devuelve null si es una combinación inválida.
DecisionSync? _try(EstadoSyncLocal estado, SenalSync senal, {int reintentos = 0}) {
  try {
    return decidir(estadoActual: estado, senal: senal, reintentos: reintentos);
  } on StateError {
    return null;
  }
}

void main() {
  final noTerminales =
      EstadoSyncLocal.values.where((e) => !e.esTerminal).toList();
  final terminales = EstadoSyncLocal.values.where((e) => e.esTerminal).toList();

  group('mapeo de los cuatro casos del ticket', () {
    test('conflicto resuelto a favor del servidor → descartado', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.esperandoResolucion,
        senal: SenalSync.resolucionGanoServidor,
        reintentos: 0,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.descartado);
      expect(d.motivo, MotivoSync.conflictoResueltoServidor);
      expect(d.registraDescarte, isTrue);
    });

    test('conflicto resuelto a favor del cliente → sincronizado', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.esperandoResolucion,
        senal: SenalSync.resolucionGanoCliente,
        reintentos: 0,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.sincronizado);
      expect(d.motivo, MotivoSync.conflictoResueltoCliente);
      expect(d.registraDescarte, isFalse);
    });

    test('resolución indeterminada → descartado/heredado_indeterminado', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.esperandoResolucion,
        senal: SenalSync.resolucionIndeterminada,
        reintentos: 0,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.descartado);
      expect(d.motivo, MotivoSync.heredadoIndeterminado);
      expect(d.registraDescarte, isTrue);
    });

    test('resolución indeterminada es inválida en enviando (solo espera)', () {
      expect(
        () => decidir(
          estadoActual: EstadoSyncLocal.enviando,
          senal: SenalSync.resolucionIndeterminada,
          reintentos: 0,
        ),
        throwsStateError,
      );
    });

    test('rechazo de negocio 4xx definitivo → descartado', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.rechazoDefinitivo,
        reintentos: 0,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.descartado);
      expect(d.motivo, MotivoSync.rechazoNegocio);
      expect(d.registraDescarte, isTrue);
    });

    test('error transitorio que agotó reintentos → descartado', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.fallaTransitoria,
        reintentos: kMaxReintentosSync - 1, // el +1 lo agota
      );
      expect(d.nuevoEstado, EstadoSyncLocal.descartado);
      expect(d.motivo, MotivoSync.reintentosAgotados);
      expect(d.registraDescarte, isTrue);
    });
  });

  group('borde de agotamiento (CTT-103)', () {
    test('falla transitoria NO agotada vuelve a pendiente e incrementa', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.fallaTransitoria,
        reintentos: 0,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.pendiente);
      expect(d.motivo, MotivoSync.errorTransitorio);
      expect(d.incrementaReintentos, isTrue);
    });

    test('el último intento (reintentos == max-1) termina, no reintenta', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.fallaTransitoria,
        reintentos: kMaxReintentosSync - 1,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.descartado);
      expect(d.incrementaReintentos, isFalse);
    });

    test('envío ok termina en sincronizado', () {
      final d = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.envioOk,
        reintentos: 0,
      );
      expect(d.nuevoEstado, EstadoSyncLocal.sincronizado);
      expect(d.motivo, isNull);
    });
  });

  group('grafo de transiciones', () {
    test('los estados terminales no aceptan NINGUNA señal', () {
      for (final t in terminales) {
        for (final s in SenalSync.values) {
          expect(
            () => decidir(estadoActual: t, senal: s, reintentos: 0),
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
          if (d != null && d.nuevoEstado != estado) {
            salidas.add(d.nuevoEstado);
          }
        }
        expect(salidas, isNotEmpty,
            reason: '$estado es un sumidero: ninguna señal lo saca de sí mismo',);
      }
    });

    test('ambos terminales son alcanzables desde pendiente', () {
      // BFS sobre el grafo partiendo de pendiente, explorando toda señal.
      final visitados = <EstadoSyncLocal>{EstadoSyncLocal.pendiente};
      final cola = <EstadoSyncLocal>[EstadoSyncLocal.pendiente];
      final reintentosPorEstado = {EstadoSyncLocal.enviando: 0};
      while (cola.isNotEmpty) {
        final actual = cola.removeAt(0);
        if (actual.esTerminal) continue;
        for (final s in SenalSync.values) {
          // Explorar ambas ramas de fallaTransitoria (agotada y no agotada).
          for (final r in [0, kMaxReintentosSync - 1]) {
            final d = _try(actual, s, reintentos: r);
            if (d != null && visitados.add(d.nuevoEstado)) {
              cola.add(d.nuevoEstado);
            }
          }
        }
      }
      expect(visitados.contains(EstadoSyncLocal.sincronizado), isTrue);
      expect(visitados.contains(EstadoSyncLocal.descartado), isTrue);
      // ignore: unused_local_variable
      reintentosPorEstado; // documentativo
    });
  });

  // ── Condición de alcance CTT-117 (tramo 2) ─────────────────────────────────
  //
  // esperando_resolucion es no terminal, pero su ÚNICA salida son las señales
  // resolucionGanoCliente/resolucionGanoServidor, que hasta el tramo 3 NINGÚN
  // código de producción emite. El test del grafo de arriba NO detecta esto:
  // verifica que decidir() tiene arista de salida, no que alguien la ejerza.
  // Este caso lo verifica y DEBE fallar hoy; el skip se auto-limpia porque el
  // tramo 3 no puede cerrarse con él puesto (mismo patrón que el skip de CTT-115).
  test('existe código de producción que emite las señales de resolución', () {
    final fuentes = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        // Excluir la definición de la propia función de decisión: buscamos un
        // EMISOR (un caller), no el switch interno de decision_sync.dart.
        .where((f) => !f.path.replaceAll(r'\', '/').endsWith(
            'lib/core/sync/decision_sync.dart',),);

    final emiteCliente = fuentes.any((f) =>
        f.readAsStringSync().contains('SenalSync.resolucionGanoCliente'),);
    final emiteServidor = fuentes.any((f) =>
        f.readAsStringSync().contains('SenalSync.resolucionGanoServidor'),);

    expect(emiteCliente && emiteServidor, isTrue,
        reason: 'Nadie emite las señales de resolución: esperando_resolucion '
            'es un sumidero hasta el tramo 3.',);
  }, skip: 'Se habilita en el tramo 3 de CTT-117 — hasta entonces '
      'esperando_resolucion no tiene salida ejercida',);
}
