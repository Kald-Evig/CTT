"""
test_items_flow.py — Flujo operativo end-to-end vía HTTP (Secciones 5.3, 6, 9).

Recorre el ciclo de vida real de un ítem a través de la API: crear proyecto e
ítem, asignar, ejecutar la cadena de estados y validar los límites de jerarquía.
Complementa a test_state_machine.py (que prueba la lógica aislada) verificando
que la capa HTTP — permisos, tenancy, serialización — encaja con el dominio.
"""

from app.config import settings


# ── Happy path: ciclo completo de un ítem ────────────────────────────────────
def test_ciclo_completo_item(client, seeded):
    h_coord = seeded.headers(seeded.coord)
    h_trab = seeded.headers(seeded.trab)
    h_resid = seeded.headers(seeded.resid)

    # 1) Coordinador crea un proyecto.
    r = client.post("/proyectos", json={"nombre": "Obra Nueva"}, headers=h_coord)
    assert r.status_code == 201, r.text
    proyecto_id = r.json()["id"]

    # 2) Coordinador crea un ítem en ese proyecto.
    r = client.post("/items",
                    json={"proyecto_id": proyecto_id, "nombre": "Excavación"},
                    headers=h_coord)
    assert r.status_code == 201, r.text
    item = r.json()
    item_id = item["id"]
    assert item["estado"] == "abierto"
    assert item["nivel_profundidad"] == 0

    # 3) Coordinador asigna el ítem al trabajador.
    r = client.post(f"/items/{item_id}/asignar",
                    json={"usuario_id": seeded.trab_id}, headers=h_coord)
    assert r.status_code == 200, r.text
    assert r.json()["asignado_a"] == seeded.trab_id

    # 4) Trabajador inicia (ABIERTO -> EN_PROGRESO).
    r = client.post(f"/items/{item_id}/transicion",
                    json={"nuevo_estado": "en_progreso"}, headers=h_trab)
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "en_progreso"

    # 5) Trabajador marca para revisión.
    r = client.post(f"/items/{item_id}/transicion",
                    json={"nuevo_estado": "pendiente_revision"}, headers=h_trab)
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "pendiente_revision"

    # 6) Residente aprueba (-> TERMINADO).
    r = client.post(f"/items/{item_id}/transicion",
                    json={"nuevo_estado": "terminado"}, headers=h_resid)
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "terminado"


# ── Permisos a nivel HTTP ────────────────────────────────────────────────────
def test_trabajador_no_puede_crear_item(client, seeded):
    r = client.post("/items",
                    json={"proyecto_id": seeded.proyecto, "nombre": "X"},
                    headers=seeded.headers(seeded.trab))
    assert r.status_code == 403


def test_transicion_no_permitida_da_409(client, seeded):
    # El ítem sembrado está ABIERTO; saltar directo a TERMINADO no es válido.
    r = client.post(f"/items/{seeded.item}/transicion",
                    json={"nuevo_estado": "terminado"},
                    headers=seeded.headers(seeded.resid))
    assert r.status_code == 409


def test_trabajador_no_asignado_no_inicia(client, seeded):
    # Crear un ítem nuevo (sin asignar) y que el trabajador intente iniciarlo.
    r = client.post("/items",
                    json={"proyecto_id": seeded.proyecto, "nombre": "Sin asignar"},
                    headers=seeded.headers(seeded.coord))
    item_id = r.json()["id"]
    r = client.post(f"/items/{item_id}/transicion",
                    json={"nuevo_estado": "en_progreso"},
                    headers=seeded.headers(seeded.trab))
    assert r.status_code == 409


# ── Flujo de problema (R1) y su cierre ───────────────────────────────────────
def test_flujo_problema_y_cierre(client, seeded):
    h_trab = seeded.headers(seeded.trab)
    h_resid = seeded.headers(seeded.resid)
    item_id = seeded.item

    # Llevar a EN_PROGRESO (el ítem sembrado está asignado al trabajador).
    client.post(f"/items/{item_id}/transicion",
                json={"nuevo_estado": "en_progreso"}, headers=h_trab)

    # Marcar problema SIN descripción -> 409.
    r = client.post(f"/items/{item_id}/transicion",
                    json={"nuevo_estado": "problema"}, headers=h_trab)
    assert r.status_code == 409

    # Con descripción -> 200.
    r = client.post(f"/items/{item_id}/transicion",
                    json={"nuevo_estado": "problema",
                          "descripcion_problema": "Maquinaria averiada"},
                    headers=h_trab)
    assert r.status_code == 200
    assert r.json()["estado"] == "problema"

    # Mientras está en problema, no se puede avanzar (R1) -> 409.
    r = client.post(f"/items/{item_id}/transicion",
                    json={"nuevo_estado": "pendiente_revision"}, headers=h_trab)
    assert r.status_code == 409

    # Residente cierra el problema -> vuelve a EN_PROGRESO.
    r = client.post(f"/items/{item_id}/cerrar-problema", headers=h_resid)
    assert r.status_code == 200
    assert r.json()["estado"] == "en_progreso"


def test_rechazo_requiere_comentario_via_api(client, seeded):
    h_trab = seeded.headers(seeded.trab)
    h_resid = seeded.headers(seeded.resid)
    item_id = seeded.item

    client.post(f"/items/{item_id}/transicion",
                json={"nuevo_estado": "en_progreso"}, headers=h_trab)
    client.post(f"/items/{item_id}/transicion",
                json={"nuevo_estado": "pendiente_revision"}, headers=h_trab)

    # Rechazo (PENDIENTE_REVISION -> EN_PROGRESO) sin comentario -> 409.
    r = client.post(f"/items/{item_id}/transicion",
                    json={"nuevo_estado": "en_progreso"}, headers=h_resid)
    assert r.status_code == 409

    # Con comentario -> 200.
    r = client.post(f"/items/{item_id}/transicion",
                    json={"nuevo_estado": "en_progreso",
                          "comentario": "Falta el sello de la inspección."},
                    headers=h_resid)
    assert r.status_code == 200
    assert r.json()["estado"] == "en_progreso"


# ── Límites de jerarquía (Sección 5.3) ───────────────────────────────────────
def test_limite_de_profundidad(client, seeded):
    h = seeded.headers(seeded.coord)
    parent_id = seeded.item  # nivel 0
    # Crear hijos encadenados hasta el nivel máximo permitido.
    for nivel_esperado in range(1, settings.MAX_NIVEL_PROFUNDIDAD + 1):
        r = client.post("/items",
                        json={"proyecto_id": seeded.proyecto,
                              "parent_item_id": parent_id,
                              "nombre": f"Sub nivel {nivel_esperado}"},
                        headers=h)
        assert r.status_code == 201, r.text
        assert r.json()["nivel_profundidad"] == nivel_esperado
        parent_id = r.json()["id"]

    # Un nivel más debe exceder el máximo -> 400.
    r = client.post("/items",
                    json={"proyecto_id": seeded.proyecto,
                          "parent_item_id": parent_id, "nombre": "Demasiado hondo"},
                    headers=h)
    assert r.status_code == 400


def test_limite_de_hijos_directos(client, seeded):
    h = seeded.headers(seeded.coord)
    # Crear un padre nuevo.
    r = client.post("/items",
                    json={"proyecto_id": seeded.proyecto, "nombre": "Padre"},
                    headers=h)
    parent_id = r.json()["id"]

    # Crear el máximo de hijos directos permitido.
    for i in range(settings.MAX_HIJOS_DIRECTOS):
        r = client.post("/items",
                        json={"proyecto_id": seeded.proyecto,
                              "parent_item_id": parent_id, "nombre": f"Hijo {i}"},
                        headers=h)
        assert r.status_code == 201, r.text

    # Uno más debe ser rechazado -> 400.
    r = client.post("/items",
                    json={"proyecto_id": seeded.proyecto,
                          "parent_item_id": parent_id, "nombre": "Hijo extra"},
                    headers=h)
    assert r.status_code == 400
