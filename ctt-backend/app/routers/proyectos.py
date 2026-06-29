"""
routers/proyectos.py — Endpoints de proyectos.

Cubre: crear proyecto, listar proyectos de la empresa, cerrar proyecto.
Permisos según matriz 2.2; aislamiento por empresa según tenancy.py.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context, requiere_empresa
from app.database import get_db
from app.enums import ProyectoEstado
from app.models import Item, ItemHistorial, Proyecto, Usuario
from app.permissions import puede
from app.schemas import (
    DashboardProyectoOut, ProyectoCreate, ProyectoHistorialEntradaOut, ProyectoOut,
)
from app.tenancy import get_proyecto_de_empresa, get_usuario_de_empresa

router = APIRouter(prefix="/proyectos", tags=["Proyectos"])


@router.post("", response_model=ProyectoOut, status_code=201)
def crear_proyecto(
    body: ProyectoCreate,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Crea un proyecto en la empresa activa (Coordinador o Admin)."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "crear_editar_proyecto"):
        raise HTTPException(403, "Su rol no puede crear proyectos.")

    # Validar que el coordinador pertenece a la misma empresa (Sección 4.2).
    if body.coordinador_principal_id:
        get_usuario_de_empresa(db, body.coordinador_principal_id, empresa_id)

    proyecto = Proyecto(
        empresa_id=empresa_id,
        nombre=body.nombre,
        descripcion=body.descripcion,
        ubicacion_nombre=body.ubicacion_nombre,
        latitud=body.latitud,
        longitud=body.longitud,
        coordinador_principal_id=body.coordinador_principal_id,
        fecha_inicio=body.fecha_inicio,
        fecha_fin_estimada=body.fecha_fin_estimada,
        created_by=ctx.usuario.id,
    )
    db.add(proyecto)
    db.commit()
    db.refresh(proyecto)
    return proyecto


@router.get("", response_model=list[ProyectoOut])
def listar_proyectos(
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista los proyectos de la empresa activa (filtrado por empresa_id)."""
    empresa_id = requiere_empresa(ctx)
    return (
        db.query(Proyecto)
        .filter(Proyecto.empresa_id == empresa_id)
        .order_by(Proyecto.created_at.desc())
        .all()
    )


# ── IMPORTANTE: /dashboard y /{id}/historial deben preceder a cualquier ruta
# ── /{proyecto_id} para que FastAPI no interprete "dashboard" como un id. ────

_DASHBOARD_SQL = text("""
SELECT
    p.id,
    p.nombre,
    p.estado,
    p.fecha_inicio,
    p.fecha_fin_estimada,
    p.created_at,
    COUNT(i.id)                                                              AS total_items,
    COALESCE(SUM(CASE WHEN i.estado = 'terminado' THEN 1 ELSE 0 END), 0)   AS items_terminados,
    COALESCE(SUM(CASE
        WHEN i.id IS NOT NULL
         AND i.id NOT IN (
             SELECT DISTINCT parent_item_id FROM items i2
             WHERE i2.proyecto_id = p.id
               AND i2.parent_item_id IS NOT NULL
         )
        THEN 1 ELSE 0 END), 0)                                              AS total_hojas,
    COALESCE(SUM(CASE
        WHEN i.estado = 'terminado'
         AND i.id IS NOT NULL
         AND i.id NOT IN (
             SELECT DISTINCT parent_item_id FROM items i2
             WHERE i2.proyecto_id = p.id
               AND i2.parent_item_id IS NOT NULL
         )
        THEN 1 ELSE 0 END), 0)                                              AS hojas_terminadas
FROM proyectos p
LEFT JOIN items i ON i.proyecto_id = p.id
WHERE p.empresa_id = :empresa_id
GROUP BY p.id, p.nombre, p.estado, p.fecha_inicio, p.fecha_fin_estimada, p.created_at
ORDER BY p.created_at DESC
""")


@router.get("/dashboard", response_model=list[DashboardProyectoOut])
def dashboard_proyectos(
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista de proyectos de la empresa con métricas de avance (CTT-42).

    Devuelve en una sola query (sin N+1):
    - pct_completo: terminados / todos los ítems del árbol × 100.
    - pct_real: hojas terminadas / hojas totales × 100.
      Una hoja es un ítem que no es padre de ningún otro.
      El filtro AND parent_item_id IS NOT NULL en el subquery evita el bug
      clásico de NOT IN con NULLs (que daría 0 hojas en proyectos jerárquicos).
    """
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "acceso_reportes"):
        raise HTTPException(403, "Su rol no tiene acceso al dashboard.")

    rows = db.execute(_DASHBOARD_SQL, {"empresa_id": empresa_id}).mappings().all()

    resultado = []
    for r in rows:
        total = r["total_items"]
        terminados = r["items_terminados"]
        hojas = r["total_hojas"]
        hojas_term = r["hojas_terminadas"]
        resultado.append(DashboardProyectoOut(
            id=r["id"],
            nombre=r["nombre"],
            estado=r["estado"],
            fecha_inicio=r["fecha_inicio"],
            fecha_fin_estimada=r["fecha_fin_estimada"],
            total_items=total,
            items_terminados=terminados,
            pct_completo=round(terminados / total * 100, 1) if total else 0.0,
            total_hojas=hojas,
            hojas_terminadas=hojas_term,
            pct_real=round(hojas_term / hojas * 100, 1) if hojas else 0.0,
        ))
    return resultado


@router.get("/{proyecto_id}/historial", response_model=list[ProyectoHistorialEntradaOut])
def historial_proyecto(
    proyecto_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Log cronológico de todos los ítems del proyecto (CTT-42).

    Agrega el historial de cambios de estado de todos los ítems del proyecto,
    incluyendo el nombre del ítem y del usuario que realizó el cambio.
    """
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "ver_log_cambios"):
        raise HTTPException(403, "Su rol no puede ver el log de cambios.")
    proyecto = get_proyecto_de_empresa(db, proyecto_id, empresa_id)

    rows = (
        db.query(ItemHistorial, Item.nombre, Usuario.nombre_completo)
        .join(Item, ItemHistorial.item_id == Item.id)
        .outerjoin(Usuario, ItemHistorial.usuario_id == Usuario.id)
        .filter(Item.proyecto_id == proyecto.id)
        .order_by(ItemHistorial.created_at)
        .all()
    )
    return [
        {
            "item_id": h.item_id,
            "item_nombre": item_nombre,
            "accion": h.accion,
            "estado_anterior": h.estado_anterior,
            "estado_nuevo": h.estado_nuevo,
            "detalle": h.detalle,
            "usuario_id": h.usuario_id,
            "nombre_usuario": nombre_usuario,
            "created_at": h.created_at,
        }
        for h, item_nombre, nombre_usuario in rows
    ]


@router.post("/{proyecto_id}/cerrar", response_model=ProyectoOut)
def cerrar_proyecto(
    proyecto_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Cierra un proyecto definitivamente (solo Admin — Sección 2.2)."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "cerrar_proyecto"):
        raise HTTPException(403, "Solo un Admin puede cerrar proyectos.")
    proyecto = get_proyecto_de_empresa(db, proyecto_id, empresa_id)
    proyecto.estado = ProyectoEstado.CERRADO
    db.commit()
    db.refresh(proyecto)
    return proyecto
