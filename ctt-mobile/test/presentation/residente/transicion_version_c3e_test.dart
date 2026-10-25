/// transicion_version_c3e_test.dart — CTT-143 C3f: tras un 409, el estado y la version del
/// ItemResidente llegan JUNTOS del servidor (se re-lee el ítem, Opción 2). Nunca se aplica una
/// version sin su estado: (estado viejo + version nueva) es una combinación que el usuario nunca
/// vio y haría que la próxima transición pisara el conflicto sin verlo (lost update). El 200
/// sigue adoptando la version del servidor (C3e); el rechazo conserva el estado anterior entero.
///
/// Arma: un ResidenteRepository FAKE que (a) registra el `version` de cada transicionarItem y
/// (b) controla qué devuelve obtenerItem en el build y en la re-lectura del 409. Verifica (del
/// código del provider): el estado mostrado y la version salen del ítem re-leído, y la 2da
/// transición usa esa version SOLO después de que el estado mostrado es el del servidor — los
/// valores salen del código, no del test.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/data/local/daos/sync_dao.dart' show ResultadoEspera;
import 'package:ctt_mobile/data/repositories/residente_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';

class _FakeResidenteRepo extends Mock implements ResidenteRepository {}

ItemResidente _item({required int? version, String estado = 'abierto'}) =>
    ItemResidente(
      id: 'it-1',
      proyectoId: 'p1',
      nivelProfundidad: 0,
      nombre: 'Tarea',
      estado: estado,
      version: version,
    );

void main() {
  late _FakeResidenteRepo repo;
  late List<int?> versiones;
  late ItemResidente servidor; // lo que devuelve obtenerItem (build y re-lectura del 409)

  setUp(() {
    repo = _FakeResidenteRepo();
    versiones = [];
    servidor = _item(version: 1, estado: 'abierto');
    when(() => repo.obtenerItem('it-1')).thenAnswer((_) async => servidor);
  });

  // Registra el `version` de cada transicionarItem, corre [alTransicionar] (para mover el
  // "servidor" que verá la re-lectura) y devuelve [resultado].
  void stubTransicion(ResultadoEspera resultado, {void Function()? alTransicionar}) {
    when(() => repo.transicionarItem(
          any(),
          any(),
          version: any(named: 'version'),
          comentario: any(named: 'comentario'),
          descripcionProblema: any(named: 'descripcionProblema'),
        )).thenAnswer((inv) async {
      versiones.add(inv.namedArguments[#version] as int?);
      alTransicionar?.call();
      return resultado;
    });
  }

  Future<void> conProvider(
    ResultadoEspera resultado,
    Future<void> Function(ItemResidenteDetalle n, ProviderContainer c) cuerpo, {
    void Function()? alTransicionar,
  }) async {
    stubTransicion(resultado, alTransicionar: alTransicionar);
    final container = ProviderContainer(
      overrides: [residenteRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(itemResidenteDetalleProvider('it-1').future);
    await cuerpo(
      container.read(itemResidenteDetalleProvider('it-1').notifier),
      container,
    );
  }

  ItemResidente leer(ProviderContainer c) =>
      c.read(itemResidenteDetalleProvider('it-1')).value!;

  test('sincronizado: la 2da transición usa la version+1 del 200', () async {
    await conProvider(
      const ResultadoEspera(EstadoSyncLocal.sincronizado, versionResultante: 2),
      (n, c) async {
        await n.transicionar(nuevoEstado: 'en_progreso');
        await n.transicionar(nuevoEstado: 'pendiente_revision');
      },
    );
    expect(versiones, [1, 2],
        reason: '1ra con la base (1); 2da con la version del 200 (2)');
  });

  test('409: re-lee el ítem; estado y version llegan JUNTOS del servidor', () async {
    // Caso a + b de C3f. El servidor avanza a v4/pendiente_revision por un cambio ajeno; tras
    // el 409 el provider re-lee el ítem y debe quedar en ESE estado con ESA version.
    await conProvider(
      const ResultadoEspera(EstadoSyncLocal.esperandoResolucion),
      (n, c) async {
        await n.transicionar(nuevoEstado: 'en_progreso'); // 1ra: base=1; 409 → re-lectura

        // (a) el estado mostrado y la version salen del ítem re-leído, JUNTOS.
        final item = leer(c);
        expect(item.estado, 'pendiente_revision',
            reason: 'el provider muestra el estado real del servidor, no el viejo');
        expect(item.version, 4, reason: 'la version llega con su estado, no sola');

        // (b) la 2da transición usa version_base=4 SOLO ahora que el estado mostrado es el real.
        await n.transicionar(nuevoEstado: 'terminado');
      },
      alTransicionar: () {
        servidor = _item(version: 4, estado: 'pendiente_revision');
      },
    );
    expect(versiones, [1, 4],
        reason: '1ra con la base (1); 2da con la version del estado real re-leído (4)');
  });

  test('409 con re-lectura fallida (sin red): conserva el estado anterior; la version no se '
      'mueve sola', () async {
    // Caso c de C3f (Opción 2): si no hay red para re-leer, NO se aplica la version sin su
    // estado; se conserva estadoAnterior COMPLETO (estado y version viejos, juntos).
    await conProvider(
      const ResultadoEspera(EstadoSyncLocal.esperandoResolucion),
      (n, c) async {
        await n.transicionar(nuevoEstado: 'en_progreso'); // 409 → re-lectura falla → anterior

        final item = leer(c);
        expect(item.estado, 'abierto', reason: 'vuelve al estado anterior entero');
        expect(item.version, 1, reason: 'la version NO cambia sin su estado');

        await n.transicionar(nuevoEstado: 'en_progreso'); // 2da: sigue con la base (1)
      },
      alTransicionar: () {
        // Tras enviar, la re-lectura del ítem falla (sin red).
        when(() => repo.obtenerItem('it-1')).thenThrow(Exception('sin red'));
      },
    );
    expect(versiones, [1, 1],
        reason: 'sin re-lectura, se conserva la base; la version no se aplica sin su estado');
  });

  test('rechazo (sin version): conserva el estado anterior entero', () async {
    await conProvider(
      const ResultadoEspera(EstadoSyncLocal.rechazada),
      (n, c) async {
        await n.transicionar(nuevoEstado: 'terminado');
        expect(leer(c).estado, 'abierto', reason: 'el ítem no cambió');
        await n.transicionar(nuevoEstado: 'terminado');
      },
    );
    expect(versiones, [1, 1], reason: 'sin version del servidor, se conserva la base');
  });
}
