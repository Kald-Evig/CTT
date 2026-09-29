/// pantalla_recuperacion.dart — CTT-130 fase 4.
///
/// Se muestra cuando la base local no pudo abrirse o migrarse. NUNCA el login: el
/// trabajador tiene que saber que su cambio no se perdió y poder sacarlo. Ofrece:
///   - Reintentar (re-corre la compuerta de arranque).
///   - Exportar los cambios pendientes a un archivo JSON (leídos con SQL crudo del
///     archivo o del respaldo, sin depender del esquema de Drift).
///
/// "Compartir" el archivo (share_plus) sería una dependencia nueva: por ahora se
/// escribe el JSON a disco y se muestra la ruta. Ver reporte de CTT-130 fase 4.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:ctt_mobile/data/local/apertura_base.dart';
import 'package:ctt_mobile/presentation/arranque/arranque_provider.dart';
import 'package:ctt_mobile/presentation/shared/mensajes.dart';

class PantallaRecuperacion extends ConsumerWidget {
  const PantallaRecuperacion({super.key, required this.error});

  final Object error;

  Future<void> _exportar(BuildContext context) async {
    try {
      final path = await rutaBase();
      // Preferir el respaldo previo a migrar si existe; si no, la base real.
      final candidatos = [
        for (final entry
            in Directory(p.dirname(path)).listSync().whereType<File>())
          if (p.basename(entry.path).startsWith('${p.basename(path)}.bak_v'))
            entry.path,
      ]..sort();
      final fuente = candidatos.isNotEmpty ? candidatos.last : path;

      final json = exportarColaPendienteJson(fuente);
      final destino = File('$path.export.json');
      await destino.writeAsString(json);
      if (context.mounted) {
        mostrarMensaje(context, 'Cambios exportados a: ${destino.path}');
      }
    } catch (e) {
      if (context.mounted) {
        mostrarMensaje(context, 'No se pudo exportar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 64),
              const SizedBox(height: 16),
              Text(
                'No se pudo abrir la base de datos local',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tus cambios sin sincronizar NO se perdieron. Podés reintentar o '
                'exportarlos para no perder trabajo.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                onPressed: () => ref.invalidate(arranqueProvider),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Exportar cambios pendientes'),
                onPressed: () => _exportar(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
