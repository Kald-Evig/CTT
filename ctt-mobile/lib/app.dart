/// app.dart — Configuración del router y tema raíz de la app.
///
/// El GoRouter redirige al usuario según su rol autenticado.
/// Las rutas privadas comprueban el estado de auth en cada navegación.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';
import 'package:ctt_mobile/presentation/auth/login_screen.dart';
import 'package:ctt_mobile/presentation/auth/perfil_notifier.dart';

part 'app.g.dart';

// ── Rutas base ────────────────────────────────────────────────────────────────

abstract final class Rutas {
  static const login = '/login';
  /// Pantalla genérica para autenticados sin rol conocido (hasta que /me esté implementado).
  static const inicio = '/inicio';
  static const trabajador = '/trabajador';
  static const residente = '/residente';
  static const coordinador = '/coordinador';
  static const admin = '/admin';
}

// ── Estado de autenticación (simplificado para la fase de cimientos) ──────────

/// Estado mínimo de auth para el router.
/// La implementación completa con FirebaseAuth va en Fase 1.2.
enum EstadoAuth { cargando, autenticado, sinSesion }

@riverpod
EstadoAuth estadoAuth(EstadoAuthRef ref) {
  final userAsync = ref.watch(firebaseAuthStreamProvider);
  return userAsync.when(
    data: (user) {
      if (user == null) return EstadoAuth.sinSesion;
      // Esperar a que /me complete antes de redirigir al router.
      // Evita mostrar /inicio como destino intermedio mientras carga el rol.
      final perfilAsync = ref.watch(perfilSesionProvider);
      if (perfilAsync.isLoading) return EstadoAuth.cargando;
      return EstadoAuth.autenticado;
    },
    loading: () => EstadoAuth.cargando,
    error: (_, __) => EstadoAuth.sinSesion,
  );
}

/// Rol del usuario en la empresa activa (primera empresa de la lista del perfil).
/// Null si no hay sesión, si /me aún está cargando o si la lista de empresas está vacía.
@riverpod
String? rolUsuarioActual(RolUsuarioActualRef ref) {
  final perfil = ref.watch(perfilSesionProvider).valueOrNull;
  if (perfil == null || perfil.empresas.isEmpty) return null;
  // Auto-selecciona la primera empresa.
  // TODO Fase 2: pantalla de selección cuando empresas.length > 1.
  return perfil.empresas.first.rol.valor;
}

// ── Router ────────────────────────────────────────────────────────────────────

@riverpod
GoRouter router(RouterRef ref) {
  final auth = ref.watch(estadoAuthProvider);
  final rol = ref.watch(rolUsuarioActualProvider);

  return GoRouter(
    initialLocation: Rutas.login,
    redirect: (context, state) {
      if (auth == EstadoAuth.cargando) return null;

      final sinSesion = auth == EstadoAuth.sinSesion;
      final enLogin = state.matchedLocation == Rutas.login;

      if (sinSesion && !enLogin) return Rutas.login;
      if (!sinSesion && enLogin) return _rutaPorRol(rol);

      return null;
    },
    routes: [
      GoRoute(
        path: Rutas.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: Rutas.inicio,
        builder: (_, __) => const _PantallaPlaceholder(titulo: 'Inicio'),
      ),
      GoRoute(
        path: Rutas.trabajador,
        builder: (_, __) => const _PantallaPlaceholder(titulo: 'Trabajador'),
      ),
      GoRoute(
        path: Rutas.residente,
        builder: (_, __) => const _PantallaPlaceholder(titulo: 'Residente'),
      ),
      GoRoute(
        path: Rutas.coordinador,
        builder: (_, __) => const _PantallaPlaceholder(titulo: 'Coordinador'),
      ),
      GoRoute(
        path: Rutas.admin,
        builder: (_, __) => const _PantallaPlaceholder(titulo: 'Admin'),
      ),
    ],
  );
}

/// Determina la ruta inicial según el rol del usuario.
String _rutaPorRol(String? rol) {
  return switch (rol) {
    'trabajador' => Rutas.trabajador,
    'residente' => Rutas.residente,
    'coordinador' => Rutas.coordinador,
    'admin' => Rutas.admin,
    // Sin rol conocido: pantalla genérica hasta que /me esté implementado.
    _ => Rutas.inicio,
  };
}

// ── Widget raíz ───────────────────────────────────────────────────────────────

class AppCTT extends ConsumerWidget {
  const AppCTT({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goRouter = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'CTT',
      debugShowCheckedModeBanner: false,
      routerConfig: goRouter,
      theme: _temaCTT(),
    );
  }
}

ThemeData _temaCTT() => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1A56DB), // Azul construcción
      ),
      useMaterial3: true,
    );

// ── Placeholder hasta que se construyan las pantallas reales ──────────────────

class _PantallaPlaceholder extends StatelessWidget {
  const _PantallaPlaceholder({required this.titulo});
  final String titulo;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(titulo)),
        body: Center(
          child: Text(
            'Pantalla $titulo — Fase 1.x',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
}
