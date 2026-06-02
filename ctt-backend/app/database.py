"""
database.py — Conexión a la base de datos y sesión por request.

Se usa SQLAlchemy 2.0 en modo SÍNCRONO para este prototipo (menor superficie de
error y 100% testeable). El DDT (Sección 3.1) apunta a async en producción; la
sintaxis declarativa de los modelos es idéntica para ambos, por lo que migrar a
AsyncSession es un cambio acotado (ver DEV_DOC.md → "Ruta a producción").
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker, Session

from app.config import settings

# `check_same_thread=False` solo aplica a SQLite (necesario con FastAPI/uvicorn).
_connect_args = (
    {"check_same_thread": False} if settings.DATABASE_URL.startswith("sqlite") else {}
)

engine = create_engine(settings.DATABASE_URL, connect_args=_connect_args)

# sessionmaker produce sesiones; cada request obtiene la suya vía get_db().
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    """Base declarativa de la que heredan todos los modelos ORM."""
    pass


def get_db() -> Session:
    """Dependencia de FastAPI: entrega una sesión y garantiza su cierre.

    Uso en un endpoint:  `db: Session = Depends(get_db)`
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
