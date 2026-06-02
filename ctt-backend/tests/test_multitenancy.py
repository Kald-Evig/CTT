"""
test_multitenancy.py — Aislamiento entre empresas (Sección 4.2).

La regla central: un usuario de la Empresa B no puede ver ni tocar datos de la
Empresa A. Se verifica a nivel HTTP (que es donde importa), comprobando que el
acceso cruzado devuelve 404 (no 403, para no revelar la existencia del dato).
"""


def test_admin_b_no_ve_proyecto_de_empresa_a(client, seeded):
    # admin_b pertenece solo a la Empresa B; lista sus proyectos: no aparece el de A.
    r = client.get("/proyectos", headers=seeded.headers(seeded.admin_b))
    assert r.status_code == 200
    ids = [p["id"] for p in r.json()]
    assert seeded.proyecto not in ids


def test_admin_b_no_accede_a_items_de_proyecto_ajeno(client, seeded):
    # Pedir los ítems del proyecto de A con credenciales de B -> 404.
    r = client.get(
        "/items",
        params={"proyecto_id": seeded.proyecto},
        headers=seeded.headers(seeded.admin_b),
    )
    assert r.status_code == 404


def test_admin_b_no_accede_a_item_de_empresa_a(client, seeded):
    r = client.get(f"/items/{seeded.item}", headers=seeded.headers(seeded.admin_b))
    assert r.status_code == 404


def test_admin_b_no_puede_transicionar_item_ajeno(client, seeded):
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "en_progreso"},
        headers=seeded.headers(seeded.admin_b),
    )
    assert r.status_code == 404


def test_usuario_de_empresa_a_si_ve_su_proyecto(client, seeded):
    # Control positivo: el admin de A sí ve su proyecto y sus ítems.
    r = client.get("/proyectos", headers=seeded.headers(seeded.admin))
    assert r.status_code == 200
    assert seeded.proyecto in [p["id"] for p in r.json()]

    r2 = client.get(
        "/items",
        params={"proyecto_id": seeded.proyecto},
        headers=seeded.headers(seeded.admin),
    )
    assert r2.status_code == 200
    assert seeded.item in [i["id"] for i in r2.json()]


def test_sin_token_es_401(client, seeded):
    r = client.get("/proyectos")
    assert r.status_code == 401
