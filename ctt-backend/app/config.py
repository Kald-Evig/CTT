"""
config.py — Configuración central de la aplicación.

Los defaults son seguros para producción (fallan cerrado). Para desarrollo local
es obligatorio setear AUTH_MODE=mock y ENV=local en el .env (ver .env.example).

Sección 3.2 del DDT: PostgreSQL 15+ (AWS RDS) y Firebase Auth son el objetivo
de producción. El swap se hace SIN tocar el resto del código: basta cambiar
DATABASE_URL y AUTH_MODE.
"""

from typing import Literal

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # ── Base de datos ────────────────────────────────────────────────────────
    DATABASE_URL: str = "postgresql+psycopg://postgres:ctt_dev@localhost:5432/ctt_dev"

    # ── Entorno ──────────────────────────────────────────────────────────────
    # "local"      -> desarrollo local (habilita AUTH_MODE=mock)
    # "production" -> producción (AUTH_MODE=mock aborta el arranque)
    ENV: Literal["local", "production"] = "production"

    # ── Autenticación ────────────────────────────────────────────────────────
    # "mock"     -> token Bearer == firebase_uid, sin validación criptográfica.
    #              Solo permitido con ENV=local. Cualquier otro valor aborta el arranque.
    # "firebase" -> valida JWT con firebase-admin (producción, Sección 4.3 del DDT).
    #              Default intencional: olvidar la variable falla cerrado (501).
    AUTH_MODE: Literal["mock", "firebase"] = "firebase"

    # ── Reglas de negocio (Sección 5.3 del DDT) ──────────────────────────────
    MAX_NIVEL_PROFUNDIDAD: int = 3          # nivel máximo permitido (0-indexado)
    MAX_HIJOS_DIRECTOS: int = 10            # máx ítems hijos por padre

    # ── Validación de RUT ────────────────────────────────────────────────────
    RUT_OBLIGATORIO: bool = False

    # ── Logging de desarrollo ────────────────────────────────────────────────
    LOG_REQUESTS: bool = True

    # ── Metadatos ────────────────────────────────────────────────────────────
    APP_NAME: str = "CTT — Field Service Management"
    APP_VERSION: str = "1.0.0-mvp"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @model_validator(mode="after")
    def _validar_combinacion_segura(self) -> "Settings":
        if self.AUTH_MODE == "mock" and self.ENV != "local":
            raise ValueError(
                f"Combinación prohibida: AUTH_MODE='mock' requiere ENV='local' "
                f"(actual ENV='{self.ENV}'). "
                f"Setear ENV=local en el .env para desarrollo local."
            )
        return self


# Instancia única reutilizada en toda la app (patrón singleton simple).
settings = Settings()
