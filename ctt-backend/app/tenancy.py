"""
tenancy.py — Aislamiento multi-tenant (Sección 4.2 del DDT).

Punto único para obtener proyectos e ítems GARANTIZANDO que pertenecen a la
empresa activa del usuario. Si un endpoint usa estos helpers, es imposible que
un usuario de la Empresa A toque datos de la Empresa B (regla central de la
Sección 4.2).
"""

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models import Item, Proyecto


def get_proyecto_de_empresa(db: Session, proyecto_id: str, empresa_id: str) -> Proyecto:
    """Devuelve el proyecto solo si pertenece a la empresa activa; si no, 404.

    Se usa 404 (no 403) para no revelar la existencia de datos de otra empresa.
    """
    proyecto = (
        db.query(Proyecto)
        .filter(Proyecto.id == proyecto_id, Proyecto.empresa_id == empresa_id)
        .first()
    )
    if proyecto is None:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado.")
    return proyecto


def get_item_de_empresa(db: Session, item_id: str, empresa_id: str) -> Item:
    """Devuelve el ítem solo si su proyecto pertenece a la empresa activa.

    Hace join con proyectos para validar el empresa_id (los ítems no llevan
    empresa_id directo; lo heredan del proyecto).
    """
    item = (
        db.query(Item)
        .join(Proyecto, Item.proyecto_id == Proyecto.id)
        .filter(Item.id == item_id, Proyecto.empresa_id == empresa_id)
        .first()
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Ítem no encontrado.")
    return item
