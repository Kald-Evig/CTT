/// transicion_version_c3e_test.dart — CTT-143 C3e: tras cada resultado, la version del
/// ItemResidente toma la que dio el servidor, para que la PRÓXIMA transición del Residente
/// no salga con la base vencida (su ítem no está en items_cache).
///
/// Arma: un ResidenteRepository FAKE que registra el `version` de cada transicionarItem y
/// devuelve un ResultadoEspera con versionResultante. Verifica (del código del provider): la
/// 2da transición usa la version que devolvió el 200 (version+1) o el 409 (version_actual) —
/// la version sale del código, no del test.
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

  setUp(() {
    repo = _FakeResidenteRepo();
    versiones = [];
    when(() => repo.obtenerItem('it-1'))
        .thenAnswer((_) async => _item(version: 1));
  });

  // Registra el `version` de cada transicionarItem y devuelve [resultado].
  void stubTransicion(ResultadoEspera resultado) {
    when(() => repo.transicionarItem(
          any(),
          any(),
          version: any(named: 'version'),
          comentario: any(named: 'comentario'),
          descripcionProblema: any(named: 'descripcionProblema'),
        )).thenAnswer((inv) async {
      versiones.add(inv.namedArguments[#version] as int?);
      return resultado;
    });
  }

  Future<void> conProvider(
    ResultadoEspera resultado,
    Future<void> Function(ItemResidenteDetalle n) cuerpo,
  ) async {
    stubTransicion(resultado);
    final container = ProviderContainer(
      overrides: [residenteRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(itemResidenteDetalleProvider('it-1').future);
    await cuerpo(
        container.read(itemResidenteDetalleProvider('it-1').notifier));
  }

  test('sincronizado: la 2da transición usa la version+1 del 200', () async {
    await conProvider(
      const ResultadoEspera(EstadoSyncLocal.sincronizado, versionResultante: 2),
      (n) async {
        await n.transicionar(nuevoEstado: 'en_progreso');
        await n.transicionar(nuevoEstado: 'pendiente_revision');
      },
    );
    expect(versiones, [1, 2],
        reason: '1ra con la base (1); 2da con la version del 200 (2)');
  });

  test('esperandoResolucion (409): la 2da transición usa version_actual', () async {
    await conProvider(
      const ResultadoEspera(EstadoSyncLocal.esperandoResolucion,
          versionResultante: 4),
      (n) async {
        await n.transicionar(nuevoEstado: 'en_progreso');
        await n.transicionar(nuevoEstado: 'problema',
            descripcionProblema: 'x');
      },
    );
    expect(versiones, [1, 4],
        reason: '1ra con la base (1); 2da con version_actual del 409 (4)');
  });

  test('sin versionResultante (rechazo): la 2da conserva la version anterior', () async {
    await conProvider(
      const ResultadoEspera(EstadoSyncLocal.rechazada),
      (n) async {
        await n.transicionar(nuevoEstado: 'terminado');
        await n.transicionar(nuevoEstado: 'terminado');
      },
    );
    expect(versiones, [1, 1], reason: 'sin version del servidor, se conserva la base');
  });
}
