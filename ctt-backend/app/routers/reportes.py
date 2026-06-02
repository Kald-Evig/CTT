"""
routers/reportes.py — Reportes del MVP (Sección 10).

Implementa los reportes como datos JSON (la "visualización en pantalla" del DDT).
La exportación a PDF (WeasyPrint) y Excel (openpyxl) está documentada como paso
siguiente en DEV_DOC.md: el cálculo ya vive aquí, solo falta el serializador de
formato. Mantenerlo así evita acoplar el cálculo al formato de salida.

Permiso: acceso_reportes (Residente parcial, Coordinador, Admin — Sección 2.2).
El alcance "parcial" del Residente se acota a los proyectos donde participa
(pendiente de cablear cuando exista la pantalla; el cálculo es idéntico).
"""

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context, requiere_empresa
from app.database import get_db
from app.enums import ItemEstado, ProblemaEstado
from app.models import Item, ItemProblema, Proyecto, Usuario
from app.permissions import puede
from app.tenancy import get_proyecto_de_empresa

router = APIRouter(prefix="/reportes", tags=["Reportes"])


def _check_acceso(ctx: AuthContext):
    if not puede(ctx.rol, "acceso_reportes"):
        raise HTTPException(403, "Su rol no tiene acceso a reportes.")


@router.get("/avance/{proyecto_id}")
def avance_por_proyecto(
    proyecto_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """% de ítems terminados vs total del proyecto (Sección 10.1)."""
    empresa_id = requiere_empresa(ctx)
    _check_acceso(ctx)
    proyecto = get_proyecto_de_empresa(db, proyecto_id, empresa_id)
    total = db.query(Item).filter(Item.proyecto_id == proyecto.id).count()
    terminados = (
        db.query(Item)
        .filter(Item.proyecto_id == proyecto.id, Item.estado == ItemEstado.TERMINADO)
        .count()
    )
    pct = round((terminados / total) * 100, 1) if total else 0.0
    return {"proyecto": proyecto.nombre, "total_items": total,
            "terminados": terminados, "porcentaje_avance": pct}


@router.get("/retrasos/{proyecto_id}")
def items_con_retraso(
    proyecto_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Ítems con fecha_limite vencida y no terminados (Sección 10.1).

    Nota (Sección 10.3): solo aplica a ítems CON fecha_limite definida.
    """
    empresa_id = requiere_empresa(ctx)
    _check_acceso(ctx)
    get_proyecto_de_empresa(db, proyecto_id, empresa_id)
    hoy = date.today()
    items = (
        db.query(Item)
        .filter(Item.proyecto_id == proyecto_id,
                Item.fecha_limite.isnot(None),
                Item.fecha_limite < hoy,
                Item.estado != ItemEstado.TERMINADO)
        .all()
    )
    return [
        {"item_id": i.id, "nombre": i.nombre, "estado": i.estado.value,
         "fecha_limite": i.fecha_limite, "dias_retraso": (hoy - i.fecha_limite).days}
        for i in items
    ]


@router.get("/problemas/{proyecto_id}")
def problemas_activos(
    proyecto_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista de ítems bloqueados por problemas abiertos, con antigüedad (Sección 10.1)."""
    empresa_id = requiere_empresa(ctx)
    _check_acceso(ctx)
    get_proyecto_de_empresa(db, proyecto_id, empresa_id)
    filas = (
        db.query(ItemProblema, Item)
        .join(Item, ItemProblema.item_id == Item.id)
        .filter(Item.proyecto_id == proyecto_id,
                ItemProblema.estado == ProblemaEstado.ABIERTO)
        .all()
    )
    return [
        {"item_id": item.id, "nombre": item.nombre,
         "descripcion": prob.descripcion,
         "antiguedad_dias": (date.today() - prob.created_at.date()).days}
        for prob, item in filas
    ]


@router.get("/actividad/{proyecto_id}")
def actividad_por_trabajador(
    proyecto_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Tareas por trabajador: terminadas / en progreso / pendientes (Sección 10.1)."""
    empresa_id = requiere_empresa(ctx)
    _check_acceso(ctx)
    get_proyecto_de_empresa(db, proyecto_id, empresa_id)

    items = (
        db.query(Item)
        .filter(Item.proyecto_id == proyecto_id, Item.asignado_a.isnot(None))
        .all()
    )
    # Agregación por trabajador.
    resumen: dict[str, dict] = {}
    for i in items:
        r = resumen.setdefault(i.asignado_a, {"terminadas": 0, "en_progreso": 0,
                                              "pendientes": 0})
        if i.estado == ItemEstado.TERMINADO:
            r["terminadas"] += 1
        elif i.estado == ItemEstado.EN_PROGRESO:
            r["en_progreso"] += 1
        else:
            r["pendientes"] += 1

    # Resolver nombres de trabajadores.
    salida = []
    for uid, conteos in resumen.items():
        u = db.query(Usuario).filter(Usuario.id == uid).first()
        salida.append({"trabajador": u.nombre_completo if u else uid, **conteos})
    return salida
