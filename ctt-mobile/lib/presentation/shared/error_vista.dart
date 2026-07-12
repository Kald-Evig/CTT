library;

import 'package:flutter/material.dart';

class ErrorVista extends StatelessWidget {
  const ErrorVista({
    super.key,
    required this.mensaje,
    required this.onReintento,
  });

  final String mensaje;
  final VoidCallback onReintento;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onReintento,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
}
