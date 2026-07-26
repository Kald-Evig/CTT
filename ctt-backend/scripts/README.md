# scripts/ — Herramientas de administración de datos

Scripts de uso manual para operaciones de mantenimiento. No forman parte de la API.
Correr siempre con el venv activado desde `ctt-backend/`.

---

## reconciliar_uids.py — Diagnóstico de UIDs Firebase ↔ BD

**SOLO LECTURA. No modifica ningún dato.**

Compara el `firebase_uid` almacenado en la tabla `usuarios` contra el UID real
que Firebase Auth reporta para cada email. Clasifica cada fila en:

- `SANO` — uid en BD coincide con Firebase
- `DESAJUSTADO` — uid en BD es incorrecto (el email existe en Firebase bajo otro uid)
- `HUÉRFANO EN BASE` — el email no existe en Firebase Auth
- `ERROR (...)` — fallo de red o timeout al consultar Firebase

### Requisitos

- `GOOGLE_APPLICATION_CREDENTIALS` apuntando al service account JSON de Firebase Admin.
- El service account debe tener el rol **Firebase Authentication Admin** (o equivalente).
- Acceso a la base de datos PostgreSQL (variable `DATABASE_URL` o default de desarrollo).

### Uso

```bash
# Activar venv
.venv\Scripts\activate          # Windows
source .venv/bin/activate       # Linux/macOS

python scripts/reconciliar_uids.py
```

### Output

```
email                     uid_en_base                       uid_en_firebase                   estado
------------------------- --------------------------------- --------------------------------- --------
usuario@ejemplo.com       abc123...                         abc123...                         SANO
otro@ejemplo.com          uid_viejo...                      uid_real...                       DESAJUSTADO
```

Al final imprime un resumen con conteos por categoría.

---

> Para **reparar** UIDs desajustados, ver `reparar_uids.py` (pendiente de revisión — no commiteado).
