/// seleccion_empresa_screen.dart — Pantalla de selección de empresa activa.
///
/// Solo aparece cuando el usuario pertenece a más de una empresa.
/// Al elegir, EmpresaActivaNotifier persiste la selección y el router
/// redirige automáticamente a la pantalla correspondiente al rol.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/auth/perfil_notifier.dart';
import 'package:ctt_mobile/presentation/empresa/empresa_activa_notifier.dart';

class SeleccionEmpresaScreen extends ConsumerWidget {
  const SeleccionEmpresaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfilAsync = ref.watch(perfilSesionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecciona tu empresa'),
        automaticallyImplyLeading: false,
      ),
      body: perfilAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (perfil) {
          if (perfil == null || perfil.empresas.isEmpty) {
            return const Center(
              child: Text('Sin empresas asignadas. Contacta a tu administrador.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: perfil.empresas.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final empresa = perfil.empresas[i];
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                leading: const CircleAvatar(
                  child: Icon(Icons.business_outlined),
                ),
                title: Text(
                  empresa.empresaNombre,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(_etiquetaRol(empresa.rol)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ref
                    .read(empresaActivaProvider.notifier)
                    .seleccionar(empresa),
              );
            },
          );
        },
      ),
    );
  }

  String _etiquetaRol(RolUsuario rol) => switch (rol) {
        RolUsuario.admin => 'Administrador',
        RolUsuario.coordinador => 'Coordinador',
        RolUsuario.residente => 'Residente',
        RolUsuario.trabajador => 'Trabajador',
      };
}
