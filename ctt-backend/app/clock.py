"""clock.py - Reloj inyectable del backend (CTT-161).

`get_now()` es la fuente unica del "ahora" para la ventana de terminados:
  - el corte de /items/mis-items (now - N*24h),
  - el sello de items.terminado_en al entrar a TERMINADO (registrar_escritura_item).

Es una dependencia FastAPI: los tests la sobrescriben con `app.dependency_overrides`
para fijar el reloj (sin monkeypatch de datetime). Devuelve UTC **naive** (convencion
del esquema: naive = UTC), de modo que la comparacion contra las columnas DateTime (sin
tz) no dependa de la zona horaria de la sesion de la base (ver CTT-161).
"""
from datetime import datetime, timezone


def get_now() -> datetime:
    """Instante actual en UTC naive."""
    return datetime.now(timezone.utc).replace(tzinfo=None)
