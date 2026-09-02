library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/core/util/formato_fecha.dart';
import 'package:ctt_mobile/domain/entities/coordinador_models.dart';
import 'package:ctt_mobile/presentation/coordinador/coordinador_providers.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';

class HistorialProyectoScreen extends ConsumerWidget {
  const HistorialProyectoScreen({super.key, required this.proyectoId});
  final String proyectoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historialAsync = ref.watch(historialProyectoProvider(proyectoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Historial del proyecto')),
      body: historialAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorVista(
          mensaje: 'No se pudo cargar el historial: $e',
          onReintento: () =>
              ref.invalidate(historialProyectoProvider(proyectoId)),
        ),
        data: (entradas) {
          if (entradas.isEmpty) {
            return const Center(
              child: Text(
                'Sin actividad registrada en este proyecto.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(historialProyectoProvider(proyectoId)),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entradas.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _EntradaTile(entrada: entradas[i]),
            ),
          );
        },
      ),
    );
  }
}

class _EntradaTile extends StatelessWidget {
  const _EntradaTile({required this.entrada});
  final HistorialProyectoEntrada entrada;

  @override
  Widget build(BuildContext context) {
    final inicial = entrada.nombreUsuario?.isNotEmpty == true
        ? entrada.nombreUsuario![0].toUpperCase()
        : '?';
    final transicion =
        entrada.estadoAnterior != null && entrada.estadoNuevo != null
            ? '${entrada.estadoAnterior} → ${entrada.estadoNuevo}'
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            child: Text(inicial, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entrada.itemNombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  _labelAccion(entrada.accion),
                  style: const TextStyle(fontSize: 13),
                ),
                if (transicion != null)
                  Text(transicion, style: const TextStyle(fontSize: 12)),
                if (entrada.detalle != null)
                  Text(entrada.detalle!, style: const TextStyle(fontSize: 12)),
                Text(
                  '${entrada.nombreUsuario ?? "Sistema"} · ${fechaHora(entrada.createdAt)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _labelAccion(String accion) => switch (accion) {
        'cambio_estado' => 'Cambio de estado',
        'cierre_problema' => 'Cierre de problema',
        'reversion_terminado' => 'Reversión de terminado',
        _ => accion,
      };
}
