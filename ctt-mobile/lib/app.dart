/// app.dart — Configuración del router y tema raíz de la app.
///
/// El GoRouter redirige al usuario según su rol autenticado.
/// Las rutas privadas comprueban el estado de auth en cada navegación.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/sync/conectividad_listener.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';
import 'package:ctt_mobile/presentation/auth/login_screen.dart';
import 'package:ctt_mobile/presentation/auth/perfil_notifier.dart';
import 'package:ctt_mobile/presentation/coordinador/conflictos_screen.dart';
import 'package:ctt_mobile/presentation/coordinador/coordinador_items_screen.dart';
import 'package:ctt_mobile/presentation/coordinador/coordinador_proyectos_screen.dart';
import 'package:ctt_mobile/presentation/coordinador/crear_item_screen.dart';
import 'package:ctt_mobile/presentation/coordinador/crear_proyecto_screen.dart';
import 'package:ctt_mobile/presentation/empresa/empresa_activa_notifier.dart';
import 'package:ctt_mobile/presentation/empresa/seleccion_empresa_screen.dart';
import 'package:ctt_mobile/presentation/residente/detalle_item_residente_screen.dart';
import 'package:ctt_mobile/presentation/residente/lista_items_residente_screen.dart';
import 'package:ctt_mobile/presentation/residente/notificaciones_screen.dart';
import 'package:ctt_mobile/presentation/trabajador/detalle_item_screen.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_screen.dart';

part 'app.g.dart';

// ── Rutas base ────────────────────────────────────────────────────────────────

abstract final class Rutas {
  static const login = '/login';
  static const seleccionEmpresa = '/seleccion-empresa';
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
      // Si /me falla (red caída, 401, etc.) volver al login.
      if (perfilAsync.hasError) return EstadoAuth.sinSesion;
      return EstadoAuth.autenticado;
    },
    loading: () => EstadoAuth.cargando,
    error: (_, __) => EstadoAuth.sinSesion,
  );
}

/// Rol en la empresa activa; null mientras no haya empresa seleccionada.
@riverpod
String? rolUsuarioActual(RolUsuarioActualRef ref) {
  final perfil = ref.watch(perfilSesionProvider).valueOrNull;
  final empresaActivaId = ref.watch(empresaActivaProvider);
  if (perfil == null || empresaActivaId == null) return null;
  final empresa = perfil.empresas
      .where((e) => e.empresaId == empresaActivaId)
      .firstOrNull;
  return empresa?.rol.valor;
}

// ── Router ────────────────────────────────────────────────────────────────────

@riverpod
GoRouter router(RouterRef ref) {
  final auth = ref.watch(estadoAuthProvider);
  final rol = ref.watch(rolUsuarioActualProvider);
  final perfil = ref.watch(perfilSesionProvider).valueOrNull;
  final empresaActiva = ref.watch(empresaActivaProvider);

  return GoRouter(
    initialLocation: Rutas.login,
    redirect: (context, state) {
      if (auth == EstadoAuth.cargando) return null;

      final sinSesion = auth == EstadoAuth.sinSesion;
      final ubicacion = state.matchedLocation;

      // Sin sesión: siempre al login.
      if (sinSesion) {
        return ubicacion == Rutas.login ? null : Rutas.login;
      }

      // Autenticado pero necesita elegir empresa.
      final multiEmpresa = (perfil?.empresas.length ?? 0) > 1;
      final necesitaSeleccion = multiEmpresa && empresaActiva == null;
      if (necesitaSeleccion) {
        return ubicacion == Rutas.seleccionEmpresa ? null : Rutas.seleccionEmpresa;
      }

      // Autenticado con empresa activa: salir del login y de la selección.
      if (ubicacion == Rutas.login || ubicacion == Rutas.seleccionEmpresa) {
        return _rutaPorRol(rol);
      }

      return null;
    },
    routes: [
      GoRoute(
        path: Rutas.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: Rutas.seleccionEmpresa,
        builder: (_, __) => const SeleccionEmpresaScreen(),
      ),
      GoRoute(
        path: Rutas.inicio,
        builder: (_, __) => const _PantallaPlaceholder(titulo: 'Inicio'),
      ),
      GoRoute(
        path: Rutas.trabajador,
        builder: (_, __) => const MisItemsScreen(),
        routes: [
          GoRoute(
            path: ':itemId',
            builder: (_, state) =>
                DetalleItemScreen(itemId: state.pathParameters['itemId']!),
          ),
        ],
      ),
      GoRoute(
        path: Rutas.residente,
        builder: (_, __) => const ListaItemsResidenteScreen(),
        routes: [
          // 'notificaciones' ANTES que ':itemId' para que GoRouter no lo capture como parámetro.
          GoRoute(
            path: 'notificaciones',
            builder: (_, __) => const NotificacionesResidenteScreen(),
          ),
          GoRoute(
            path: ':itemId',
            builder: (_, state) => DetalleItemResidenteScreen(
              itemId: state.pathParameters['itemId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: Rutas.coordinador,
        builder: (_, __) => const CoordinadorProyectosScreen(),
        routes: [
          // Rutas literales ANTES que ':proyectoId/items' para evitar que GoRouter
          // capture 'notificaciones', 'crear-proyecto' o 'conflictos' como parámetro.
          GoRoute(
            path: 'notificaciones',
            builder: (_, __) => const NotificacionesResidenteScreen(),
          ),
          GoRoute(
            path: 'crear-proyecto',
            builder: (_, __) => const CrearProyectoScreen(),
          ),
          GoRoute(
            path: 'conflictos',
            builder: (_, __) => const ConflictosScreen(),
          ),
          GoRoute(
            path: ':proyectoId/items',
            builder: (_, state) => CoordinadorItemsScreen(
              proyectoId: state.pathParameters['proyectoId']!,
            ),
            routes: [
              // 'nuevo' ANTES que ':itemId' — literal path primero.
              GoRoute(
                path: 'nuevo',
                builder: (_, state) => CrearItemScreen(
                  proyectoId: state.pathParameters['proyectoId']!,
                ),
              ),
              GoRoute(
                path: ':itemId',
                builder: (_, state) => DetalleItemResidenteScreen(
                  itemId: state.pathParameters['itemId']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Rutas.admin,
        builder: (_, __) => const _PantallaPlaceholder(
          titulo: 'Admin',
          icono: Icons.admin_panel_settings,
        ),
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
    // Activa el listener de conectividad para flush inmediato al recuperar señal.
    ref.watch(conectividadListenerProvider);
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
  const _PantallaPlaceholder({required this.titulo, this.icono});
  final String titulo;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: icono != null ? Icon(icono) : null,
          title: Text(titulo),
        ),
        body: Center(
          child: Text(
            'Pantalla $titulo — Fase 1.x',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
}
