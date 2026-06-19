"""
test_sync_conflictos.py — Tests end-to-end para GET /sync/conflictos y
POST /sync/conflictos/{id}/resolver (Sección 8.4).

Cubre: resolución exitosa (local y servidor), conflicto ya resuelto,
permisos por rol, filtro ?estado=, comentario preservado (Fix A),
cierre de problema huérfano (Fix B), y estado obsoleto (Fix C).
"""

import pytest

from app.enums import ConflictoEstado, ItemEstado, ProblemaEstado
from app.models import ItemComentario, ItemProblema, SyncConflicto


# ── Helpers ───────────────────────────────────────────────────────────────────

def _conflicto(db, seeded, *, cambio_local=None, cambio_servidor=None,
               estado=ConflictoEstado.PENDIENTE) -> SyncConflicto:
    """Crea y persiste un SyncConflicto básico para el ítem del fixture seeded."""
    c = SyncConflicto(
        item_id=seeded.item,
        cambio_local=cambio_local or {"estado": "en_progreso", "comentario": None},
        cambio_servidor=cambio_servidor or {"estado": "abierto"},
        dispositivo_id="test-device",
        usuario_id=seeded.trab_id,
        estado=estado,
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return c


def _h(seeded, uid):
    return seeded.headers(uid, seeded.emp_a)


# ── GET /sync/conflictos ──────────────────────────────────────────────────────

def test_get_conflictos_default_devuelve_pendientes(client, seeded, db):
    _conflicto(db, seeded)
    _conflicto(db, seeded, estado=ConflictoEstado.RESUELTO)

    r = client.get("/sync/conflictos", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    data = r.json()
    # Sin ?estado= solo retorna pendientes.
    assert len(data) == 1
    assert data[0]["estado"] == "pendiente"
    # Verifica que los campos nuevos están presentes.
    assert "resuelto_por" in data[0]
    assert "resuelto_at" in data[0]


def test_get_conflictos_filtro_estado_resuelto(client, seeded, db):
    _conflicto(db, seeded)
    _conflicto(db, seeded, estado=ConflictoEstado.RESUELTO)

    r = client.get("/sync/conflictos?estado=resuelto", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data) == 1
    assert data[0]["estado"] == "resuelto"


def test_get_conflictos_estado_invalido_es_422(client, seeded):
    r = client.get("/sync/conflictos?estado=inventado", headers=_h(seeded, seeded.coord))
    assert r.status_code == 422, r.text


# ── POST /sync/conflictos/{id}/resolver — casos base ─────────────────────────

def test_resolver_local_aplica_estado_al_item(client, seeded, db):
    """version_ganadora='local' aplica cambio_local.estado al item."""
    # cambio_servidor coincide con el estado actual del ítem (abierto) → Fix C no dispara.
    c = _conflicto(db, seeded,
                   cambio_local={"estado": "en_progreso", "comentario": None},
                   cambio_servidor={"estado": "abierto"})

    r = client.post(
        f"/sync/conflictos/{c.id}/resolver",
        json={"version_ganadora": "local"},
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["estado"] == "resuelto"
    assert body["version_ganadora"] == "local"
    assert body["resuelto_por"] == seeded.coord_id

    # Verificar que el item realmente cambió en BD.
    db.expire_all()
    from app.models import Item
    item = db.query(Item).filter(Item.id == seeded.item).first()
    assert item.estado == ItemEstado.EN_PROGRESO


def test_resolver_servidor_no_modifica_item(client, seeded, db):
    """version_ganadora='servidor' deja el item en su estado actual."""
    c = _conflicto(db, seeded,
                   cambio_local={"estado": "en_progreso", "comentario": None},
                   cambio_servidor={"estado": "abierto"})

    r = client.post(
        f"/sync/conflictos/{c.id}/resolver",
        json={"version_ganadora": "servidor"},
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 200, r.text

    db.expire_all()
    from app.models import Item
    item = db.query(Item).filter(Item.id == seeded.item).first()
    assert item.estado == ItemEstado.ABIERTO


# ── POST — guardia: conflicto ya resuelto ─────────────────────────────────────

def test_resolver_conflicto_ya_resuelto_devuelve_409(client, seeded, db):
    c = _conflicto(db, seeded, estado=ConflictoEstado.RESUELTO)

    r = client.post(
        f"/sync/conflictos/{c.id}/resolver",
        json={"version_ganadora": "local"},
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 409, r.text
    assert "ya fue resuelto" in r.json()["detail"]

    # El estado del conflicto no debe haber cambiado.
    db.expire_all()
    c_db = db.query(SyncConflicto).filter(SyncConflicto.id == c.id).first()
    assert c_db.estado == ConflictoEstado.RESUELTO


# ── POST — permisos ───────────────────────────────────────────────────────────

def test_resolver_trabajador_devuelve_403(client, seeded, db):
    c = _conflicto(db, seeded)
    r = client.post(
        f"/sync/conflictos/{c.id}/resolver",
        json={"version_ganadora": "local"},
        headers=_h(seeded, seeded.trab),
    )
    assert r.status_code == 403, r.text


def test_resolver_residente_devuelve_403(client, seeded, db):
    c = _conflicto(db, seeded)
    r = client.post(
        f"/sync/conflictos/{c.id}/resolver",
        json={"version_ganadora": "local"},
        headers=_h(seeded, seeded.resid),
    )
    assert r.status_code == 403, r.text


# ── Fix A — comentario preservado ─────────────────────────────────────────────

def test_resolver_local_con_comentario_crea_item_comentario(client, seeded, db):
    """Si version_ganadora='local' y cambio_local tiene comentario, queda en BD."""
    c = _conflicto(db, seeded,
                   cambio_local={"estado": "en_progreso", "comentario": "Iniciando con retraso"},
                   cambio_servidor={"estado": "abierto"})

    r = client.post(
        f"/sync/conflictos/{c.id}/resolver",
        json={"version_ganadora": "local"},
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 200, r.text

    db.expire_all()
    comentario = (
        db.query(ItemComentario)
        .filter(ItemComentario.item_id == seeded.item)
        .first()
    )
    assert comentario is not None
    assert "Iniciando con retraso" in comentario.texto
    assert "[Resolución de conflicto de sync]" in comentario.texto
    assert comentario.usuario_id == seeded.coord_id


def test_resolver_servidor_no_crea_comentario(client, seeded, db):
    """Si version_ganadora='servidor', el comentario del cambio local se descarta."""
    c = _conflicto(db, seeded,
                   cambio_local={"estado": "en_progreso", "comentario": "Debería perderse"},
                   cambio_servidor={"estado": "abierto"})

    r = client.post(
        f"/sync/conflictos/{c.id}/resolver",
        json={"version_ganadora": "servidor"},
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 200, r.text

    db.expire_all()
    comentario = (
        db.query(ItemComentario)
        .filter(ItemComentario.item_id == seeded.item)
        .first()
    )
    assert comentario is None


# ── Fix B — problema huérfano cerrado ─────────────────────────────────────────

def test_resolver_saca_de_problema_cierra_problema_abierto(client, seeded, db):
    """version_ganadora='local' con estado local != problema cierra ItemProblema abierto."""
    from app.models import Item
    item = db.query(Item).filter(Item.id == seeded.item).first()
    item.estado = ItemEstado.PROBLEMA
    problema = ItemProblema(
        item_id=seeded.item,
        reportado_por=seeded.trab_id,
        descripcion="Falta material",
        estado=ProblemaEstado.ABIERTO,
    )
    db.add(problema)
    db.commit()

    # cambio_servidor="problema" coincide con el estado actual → Fix C no dispara.
    c = _conflicto(db, seeded,
                   cambio_local={"estado": "en_progreso", "comentario": None},
                   cambio_servidor={"estado": "problema"})

    r = client.post(
        f"/sync/conflictos/{c.id}/resolver",
        json={"version_ganadora": "local"},
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 200, r.text

    db.expire_all()
    problema_db = db.query(ItemProblema).filter(ItemProblema.id == problema.id).first()
    assert problema_db.estado == ProblemaEstado.CERRADO
    assert problema_db.cerrado_por == seeded.coord_id
    assert problema_db.cerrado_at is not None


def test_resolver_a_problema_no_cierra_problemas(client, seeded, db):
    """version_ganadora='servidor' con item ya en PROBLEMA deja el ItemProblema abierto."""
    from app.models import Item
    item = db.query(Item).filter(Item.id == seeded.item).first()
    item.estado = ItemEstado.PROBLEMA
    problema = ItemProblema(
        item_id=seeded.item,
        reportado_por=seeded.trab_id,
        descripcion="Problema vigente",
        estado=ProblemaEstado.ABIERTO,
    )
    db.add(problema)
    db.commit()

    # version_ganadora="servidor": el item permanece en PROBLEMA → Fix B no cierra nada.
    c = _conflicto(db, seeded,
                   cambio_local={"estado": "en_progreso", "comentario": None},
                   cambio_servidor={"estado": "problema"})

    r = client.post(
        f"/sync/conflictos/{c.id}/resolver",
        json={"version_ganadora": "servidor"},
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 200, r.text

    db.expire_all()
    problema_db = db.query(ItemProblema).filter(ItemProblema.id == problema.id).first()
    assert problema_db.estado == ProblemaEstado.ABIERTO


# ── Fix C — estado obsoleto ───────────────────────────────────────────────────

def test_resolver_estado_obsoleto_devuelve_409_y_conflicto_sigue_pendiente(
    client, seeded, db
):
    """Fix C: cambio_servidor.estado difiere del estado actual del item → 409.

    El conflicto debe quedar PENDIENTE (no se marca resuelto).
    """
    # El conflicto capturó servidor='en_progreso', pero el ítem está en ABIERTO.
    c = _conflicto(db, seeded,
                   cambio_local={"estado": "pendiente_revision", "comentario": None},
                   cambio_servidor={"estado": "en_progreso"})

    r = client.post(
        f"/sync/conflictos/{c.id}/resolver",
        json={"version_ganadora": "local"},
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 409, r.text
    detail = r.json()["detail"]
    assert "capturado" in detail
    assert "en_progreso" in detail

    # El conflicto sigue pendiente.
    db.expire_all()
    c_db = db.query(SyncConflicto).filter(SyncConflicto.id == c.id).first()
    assert c_db.estado == ConflictoEstado.PENDIENTE
