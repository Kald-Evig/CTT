"""
routers/proyectos.py — Endpoints de proyectos.

Cubre: crear proyecto, listar proyectos de la empresa, cerrar proyecto.
Permisos según matriz 2.2; aislamiento por empresa según tenancy.py.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context, requiere_empresa
from app.database import get_db
from app.enums import ProyectoEstado
from app.models import Proyecto
from app.permissions import puede
from app.schemas import ProyectoCreate, ProyectoOut
from app.tenancy import get_proyecto_de_empresa

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
