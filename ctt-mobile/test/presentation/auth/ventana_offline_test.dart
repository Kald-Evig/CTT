/// ventana_offline_test.dart — CTT-138 commit 4.
///
/// Lógica pura de la ventana offline por rol y el texto "verificado hace X".
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/presentation/auth/ventana_offline.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 10, 12);

  group('ventanaPorRol', () {
    test('Trabajador 14 d, Residente 3 d, resto null', () {
      expect(ventanaPorRol('trabajador'), const Duration(days: 14));
      expect(ventanaPorRol('residente'), const Duration(days: 3));
      expect(ventanaPorRol('coordinador'), isNull);
      expect(ventanaPorRol('admin'), isNull);
      expect(ventanaPorRol(''), isNull);
    });
  });

  group('ventanaVencida', () {
    test('Trabajador dentro de 14 d → no vencida', () {
      expect(
        ventanaVencida(
          rol: 'trabajador',
          ultimoContacto: ahora.subtract(const Duration(days: 13)),
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('Trabajador pasados 14 d → vencida', () {
      expect(
        ventanaVencida(
          rol: 'trabajador',
          ultimoContacto: ahora.subtract(const Duration(days: 15)),
          ahora: ahora,
        ),
        isTrue,
      );
    });

    test('Residente dentro de 3 d → no vencida; pasados 3 d → vencida', () {
      expect(
        ventanaVencida(
          rol: 'residente',
          ultimoContacto: ahora.subtract(const Duration(days: 2)),
          ahora: ahora,
        ),
        isFalse,
      );
      expect(
        ventanaVencida(
          rol: 'residente',
          ultimoContacto: ahora.subtract(const Duration(days: 4)),
          ahora: ahora,
        ),
        isTrue,
      );
    });

    test('rol sin ventana (coordinador) → vencida (conservador)', () {
      expect(
        ventanaVencida(rol: 'coordinador', ultimoContacto: ahora, ahora: ahora),
        isTrue,
      );
    });

    test('sin último contacto → vencida', () {
      expect(
        ventanaVencida(rol: 'trabajador', ultimoContacto: null, ahora: ahora),
        isTrue,
      );
    });
  });

  group('verificadoHaceTexto', () {
    test('minutos / horas / días / null', () {
      expect(verificadoHaceTexto(const Duration(minutes: 30)), 'hace 30 min');
      expect(verificadoHaceTexto(const Duration(hours: 5)), 'hace 5 h');
      expect(verificadoHaceTexto(const Duration(days: 2)), 'hace 2 d');
      expect(verificadoHaceTexto(null), 'sin registro');
    });
  });
}
