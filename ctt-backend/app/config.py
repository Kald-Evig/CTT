"""
config.py — Configuración central de la aplicación.

Toda la configuración se lee de variables de entorno (con defaults seguros para
desarrollo). Esto permite que el MISMO código corra como:
  - Prototipo local  : SQLite + auth mock   (defaults de este archivo)
  - Producción       : PostgreSQL + Firebase (definiendo las variables de entorno)

Sección 3.2 del DDT: PostgreSQL 15+ (AWS RDS) y Firebase Auth son el objetivo
de producción. El swap se hace SIN tocar el resto del código: basta cambiar
DATABASE_URL y AUTH_MODE.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # ── Base de datos ────────────────────────────────────────────────────────
    # Default: SQLite local autocontenido. Para producción, definir p. ej.:
    #   DATABASE_URL=postgresql+psycopg://user:pass@host:5432/ctt
    DATABASE_URL: str = "sqlite:///./ctt_dev.db"

    # ── Autenticación ────────────────────────────────────────────────────────
    # "mock"     -> resuelve el usuario desde un token simple (demo, sin Firebase)
    # "firebase" -> valida JWT con firebase-admin (producción, Sección 4.3 del DDT)
    AUTH_MODE: str = "mock"

    # ── Reglas de negocio (Sección 5.3 del DDT) ──────────────────────────────
    # Profundidad del árbol de ítems. El DDT es ambiguo ("máximo 4" vs
    # "0=raíz, máx 4 niveles"); aquí se interpreta como 4 NIVELES de ítem
    # (nivel_profundidad 0..3), según el árbol narrativo:
    #   Ítem(0) -> Sub L1(1) -> Sub L2(2) -> Sub L3(3)
    # Esta ambigüedad está señalada en DEV_DOC.md para que el equipo la confirme.
    MAX_NIVEL_PROFUNDIDAD: int = 3          # nivel máximo permitido (0-indexado)
    MAX_HIJOS_DIRECTOS: int = 10            # máx ítems hijos por padre

    # ── Metadatos ────────────────────────────────────────────────────────────
    APP_NAME: str = "CTT — Field Service Management"
    APP_VERSION: str = "1.0.0-mvp"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


# Instancia única reutilizada en toda la app (patrón singleton simple).
settings = Settings()
