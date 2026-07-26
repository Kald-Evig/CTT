"""
test_config.py — Tests del endurecimiento de configuración (CTT-88 Etapa 0).
"""

import pytest
from pydantic import ValidationError

from app.config import Settings


def test_auth_mode_invalido_rechaza():
    """Valor fuera de {"mock", "firebase"} debe fallar al construir Settings."""
    with pytest.raises(ValidationError):
        Settings(AUTH_MODE="dev", ENV="local")


def test_auth_mode_invalido_typo_rechaza():
    """Typo común — 'Mock' con mayúscula también debe rechazarse."""
    with pytest.raises(ValidationError):
        Settings(AUTH_MODE="Mock", ENV="local")


def test_mock_en_production_rechaza():
    """AUTH_MODE=mock + ENV=production es combinación prohibida."""
    with pytest.raises(ValidationError):
        Settings(AUTH_MODE="mock", ENV="production")


def test_mock_en_local_arranca():
    """AUTH_MODE=mock + ENV=local es la combinación válida para desarrollo local."""
    s = Settings(AUTH_MODE="mock", ENV="local")
    assert s.AUTH_MODE == "mock"
    assert s.ENV == "local"


def test_firebase_en_production_arranca():
    """AUTH_MODE=firebase + ENV=production es la configuración de producción válida."""
    s = Settings(AUTH_MODE="firebase", ENV="production")
    assert s.AUTH_MODE == "firebase"
    assert s.ENV == "production"
