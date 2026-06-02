"""
routers/plataforma.py — Acciones de plataforma (Super Admin, Sección 2.1 y 7.5).

El Super Admin gestiona tenants (empresas). No participa en operaciones de obra,
por eso estas rutas no exigen empresa activa, solo el flag es_super_admin.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context
from app.database import get_db
from app.enums import EmpresaEstado
from app.models import Empresa
from app.schemas import EmpresaCreate, EmpresaOut

router = APIRouter(prefix="/plataforma", tags=["Plataforma (Super Admin)"])


@router.post("/empresas", response_model=EmpresaOut, status_code=201)
def crear_empresa(
    body: EmpresaCreate,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Crea una empresa (tenant). Solo Super Admin (Sección 2.2)."""
    if not ctx.es_super_admin:
        raise HTTPException(403, "Solo el Super Admin puede crear empresas.")
    if db.query(Empresa).filter(Empresa.rut_empresa == body.rut_empresa).first():
        raise HTTPException(409, "Ya existe una empresa con ese RUT.")
    empresa = Empresa(
        nombre=body.nombre,
        rut_empresa=body.rut_empresa,
        email_contacto=body.email_contacto,
        plan=body.plan,
    )
    db.add(empresa)
    db.commit()
    db.refresh(empresa)
    return empresa


@router.post("/empresas/{empresa_id}/suspender", response_model=EmpresaOut)
def suspender_empresa(
    empresa_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Suspende una empresa. Solo Super Admin."""
    if not ctx.es_super_admin:
        raise HTTPException(403, "Solo el Super Admin puede suspender empresas.")
    empresa = db.query(Empresa).filter(Empresa.id == empresa_id).first()
    if empresa is None:
        raise HTTPException(404, "Empresa no encontrada.")
    empresa.estado = EmpresaEstado.SUSPENDIDO
    db.commit()
    db.refresh(empresa)
    return empresa
