/// defensa_sesion_test.dart — CTT-147. Tests del controlador puro de la defensa.
///
/// Sin timers reales, sin Riverpod, sin Firebase ni sistema de archivos real: todas las
/// dependencias son fakes. Cada test ejercita además su camino de error / su rama negativa.
library;

import 'dart:io' show FileSystemException;

import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/security/defensa_sesion.dart';

class _MarcasFake implements MarcasDefensa {
  bool sanar = false;
  bool recienSanado = false;

  @override
  bool get haySanar => sanar;
  @override
  bool get hayRecienSanado => recienSanado;
  @override
  void marcarSanar() => sanar = true;
  @override
  void quitarSanar() => sanar = false;
  @override
  void marcarRecienSanado() => recienSanado = true;
  @override
  void quitarRecienSanado() => recienSanado = false;
}

class _ArchivosFake implements ArchivosSharedPrefs {
  _ArchivosFake(this._nombres);
  List<String> _nombres;
  final borrados = <String>[];
  bool lanzarAlBorrar = false;

  @override
  List<String> nombres() => List.of(_nombres);

  @override
  void borrar(String nombre) {
    if (lanzarAlBorrar) throw const FileSystemException('fallo de borrado simulado');
    borrados.add(nombre);
    _nombres = _nombres.where((n) => n != nombre).toList();
  }
}

void main() {
  const store =
      'com.google.firebase.auth.api.Store.W0RFRkFVTFRd+MTo3NTQz.xml';
  const crypto =
      'com.google.firebase.auth.api.crypto.W0RFRkFVTFRd+MTo3NTQz.xml';

  group('Fase 1 — decisión y efectos', () {
    test('se activa con cola NO vacía: marca sanar, registra evento, conserva el token',
        () async {
      final marcas = _MarcasFake();
      final defensa = DefensaSesion(marcas);
      var eventos = 0;
      var tokenLimpiado = false;

      final activa = await defensa.ejecutarFase1(
        hayUsuarioFirebase: false,
        hayToken: true,
        contarPendientes: () async => 3,
        limpiarToken: () async => tokenLimpiado = true,
        registrarEvento: () => eventos++,
      );

      expect(activa, isTrue);
      expect(marcas.haySanar, isTrue);
      expect(eventos, 1);
      expect(tokenLimpiado, isFalse); // cola no vacía → se conserva (headless sigue drenando)
    });

    test('se activa con cola vacía: además limpia el token', () async {
      final marcas = _MarcasFake();
      final defensa = DefensaSesion(marcas);
      var tokenLimpiado = false;

      final activa = await defensa.ejecutarFase1(
        hayUsuarioFirebase: false,
        hayToken: true,
        contarPendientes: () async => 0,
        limpiarToken: () async => tokenLimpiado = true,
        registrarEvento: () {},
      );

      expect(activa, isTrue);
      expect(marcas.haySanar, isTrue);
      expect(tokenLimpiado, isTrue);
    });

    test('NO se activa en logout (sin token): no marca ni registra', () async {
      final marcas = _MarcasFake();
      final defensa = DefensaSesion(marcas);
      var eventos = 0;

      final activa = await defensa.ejecutarFase1(
        hayUsuarioFirebase: false,
        hayToken: false,
        contarPendientes: () async => 0,
        limpiarToken: () async {},
        registrarEvento: () => eventos++,
      );

      expect(activa, isFalse);
      expect(marcas.haySanar, isFalse);
      expect(eventos, 0);
    });

    test('NO se activa en arranque sano (usuario de Firebase presente)', () async {
      final marcas = _MarcasFake();
      final defensa = DefensaSesion(marcas);

      final activa = await defensa.ejecutarFase1(
        hayUsuarioFirebase: true,
        hayToken: true,
        contarPendientes: () async => 0,
        limpiarToken: () async {},
        registrarEvento: () {},
      );

      expect(activa, isFalse);
      expect(marcas.haySanar, isFalse);
    });

    test('NO se activa con la marca "recién sanado" (anti-bucle)', () async {
      final marcas = _MarcasFake()..recienSanado = true;
      final defensa = DefensaSesion(marcas);

      final activa = await defensa.ejecutarFase1(
        hayUsuarioFirebase: false,
        hayToken: true,
        contarPendientes: () async => 0,
        limpiarToken: () async {},
        registrarEvento: () {},
      );

      expect(activa, isFalse);
      expect(marcas.haySanar, isFalse);
    });
  });

  group('Fase 2 — sanar', () {
    test('borra SOLO Store y crypto, pone recién-sanado y quita sanar', () {
      final marcas = _MarcasFake()..sanar = true;
      final archivos = _ArchivosFake([
        store,
        crypto,
        'FlutterSecureStorage.xml',
        'com.google.firebase.crashlytics.xml',
        'flutter_workmanager_plugin.xml',
      ]);
      final defensa = DefensaSesion(marcas);

      final borrados = defensa.sanarFase2(archivos);

      expect(borrados, 2);
      expect(archivos.borrados, unorderedEquals([store, crypto]));
      expect(marcas.hayRecienSanado, isTrue);
      expect(marcas.haySanar, isFalse);
    });

    test('sin la marca "sanar" no hace nada', () {
      final marcas = _MarcasFake(); // sanar = false
      final archivos = _ArchivosFake([store, crypto]);
      final defensa = DefensaSesion(marcas);

      final borrados = defensa.sanarFase2(archivos);

      expect(borrados, 0);
      expect(archivos.borrados, isEmpty);
      expect(marcas.hayRecienSanado, isFalse);
    });

    test('si el borrado falla: NO lanza, conserva la marca sanar y reporta el error', () {
      final marcas = _MarcasFake()..sanar = true;
      final archivos = _ArchivosFake([store, crypto])..lanzarAlBorrar = true;
      final defensa = DefensaSesion(marcas);
      Object? errorReportado;

      final borrados = defensa.sanarFase2(
        archivos,
        alError: (e, _) => errorReportado = e,
      );

      expect(borrados, 0);
      expect(marcas.haySanar, isTrue); // queda para reintentar
      expect(marcas.hayRecienSanado, isFalse);
      expect(errorReportado, isA<FileSystemException>());
    });
  });

  group('esArchivoFirebaseAuth — patrones exactos', () {
    test('acepta Store/crypto .xml y rechaza el resto', () {
      expect(esArchivoFirebaseAuth(store), isTrue);
      expect(esArchivoFirebaseAuth(crypto), isTrue);
      // Mismo prefijo pero sin .xml → no.
      expect(esArchivoFirebaseAuth('com.google.firebase.auth.api.Store.X'), isFalse);
      // Otros archivos de Firebase/Flutter → no.
      expect(esArchivoFirebaseAuth('FlutterSecureStorage.xml'), isFalse);
      expect(esArchivoFirebaseAuth('com.google.firebase.crashlytics.xml'), isFalse);
      expect(esArchivoFirebaseAuth('FirebaseHeartBeat.xml'), isFalse);
    });
  });

  test('login exitoso quita la marca "recién sanado"', () {
    final marcas = _MarcasFake()..recienSanado = true;
    DefensaSesion(marcas).alLoginExitoso();
    expect(marcas.hayRecienSanado, isFalse);
  });
}
