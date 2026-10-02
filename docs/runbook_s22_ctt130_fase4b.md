# Runbook — Sesión de runtime S22 · CTT-130 fase 4b

**Objetivo:** validar en un Samsung S22 real: (R1) arranque limpio, (R2) la cola
sobrevive a una reinstalación, (R3) la base NO vuelve tras backup/restore (fase 6),
(R4) el rescate automático de punta a punta.

> **NO ejecutar nada en el teléfono hasta que Kald confirme que está conectado**
> (`adb devices` lista el S22). El reset de datos de la app está autorizado por Kald.
> La huérfana de CTT-127 ya está registrada: no hace falta preservarla.

## Convenciones

- **[KALD]** = acción física en el teléfono o dato que aporta Kald.
- **[VOS]** = comando que corre el agente desde el PC (adb / build / sqlite / psql).
- Paquete: `cl.ctt.ctt_mobile`
- Base en el dispositivo: `/data/data/cl.ctt.ctt_mobile/app_flutter/ctt_local.db`
  (+ `-wal`, `-shm`). `getApplicationDocumentsDirectory()` → `app_flutter/`.
- Estados NO terminales de `sync_pendientes`: `pendiente`, `enviando`, `esperando_resolucion`.
- `PRAGMA user_version` normal = **6**. La app soporta hasta v6.
- Lectura/edición de la base: se **saca con `run-as`** (build debug) y se consulta en
  el PC con Python (`sqlite3` del stdlib). Por eso el build debe ser **debug/debuggable**.

## Prerrequisitos (confirmar ANTES de empezar)

1. **[KALD]** El S22 conectado y autorizado: `adb devices` lo lista.
2. **[KALD]** URL del backend en el tailnet, ej. `http://100.x.y.z:8000`. → `<TAILNET_URL>`.
3. **[KALD]** Cuenta Firebase de **Luis** operativa: email `luis@andessur.cl` + contraseña
   conocida. En modo `mock` la app igual inicia sesión con Firebase (email/contraseña) y
   guarda el `uid` como token; el `firebase_uid` sembrado es `pCcukEA7BfP4SiOAZNaeSkxAHY32`
   (seed.py). Sin esa cuenta no hay login.
4. **[VOS/KALD] ctt_dev (Postgres) debe tener la tabla `cola_rescate` para R4.** El dev
   usa `alembic upgrade head` (no `create_all`, CTT-49) y la migración `522cc1d85034` aún
   no está aplicada. **Por la regla de dry-run en ctt_dev, mostrar el SQL y esperar el OK
   de Kald antes de aplicar** (ver R4, paso 0).
5. **[VOS]** `AUTH_MODE` del build del cliente = el del backend (hoy `mock`). Debe coincidir.

---

## R1 — Preparación (arranque limpio)

0. **[KALD]** Confirma teléfono conectado y pasa `<TAILNET_URL>`.
1. **[VOS]** Reset de datos (autorizado):
   ```
   adb shell pm clear cl.ctt.ctt_mobile
   ```
2. **[VOS]** Build debug apuntando al tailnet, con AUTH_MODE explícito:
   ```
   cd ctt-mobile
   flutter build apk --debug \
     --dart-define=API_BASE_URL=<TAILNET_URL> \
     --dart-define=AUTH_MODE=mock
   ```
3. **[VOS]** Instalar:
   ```
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```
4. **[KALD]** Abrir la app e iniciar sesión como **Luis** (`luis@andessur.cl`).
5. **[VOS]** Verificar que la base se creó en v6:
   ```
   adb exec-out run-as cl.ctt.ctt_mobile sh -c 'ls -l app_flutter/' 
   adb exec-out run-as cl.ctt.ctt_mobile sh -c 'cat app_flutter/ctt_local.db' > s22_r1.db
   python -c "import sqlite3;c=sqlite3.connect('s22_r1.db');print('user_version=',c.execute('PRAGMA user_version').fetchone()[0])"
   ```

**Esperado:**
- `app_flutter/` contiene `ctt_local.db`. **Dónde mirar:** salida de `ls`.
- `user_version = 6`. **Dónde mirar:** salida de Python.
- La app queda en la pantalla principal logueada como Luis. **Dónde mirar:** pantalla.

---

## R2 — La cola sobrevive a una reinstalación

1. **[KALD]** Activar **modo avión**.
2. **[KALD]** En la app, hacer **2–3 cambios de estado** de ítems (cada cambio encola una
   fila en `sync_pendientes`).
3. **[VOS]** Leer la cola (sacar las tres piezas por si hay WAL sin consolidar):
   ```
   for f in ctt_local.db ctt_local.db-wal ctt_local.db-shm; do \
     adb exec-out run-as cl.ctt.ctt_mobile sh -c "cat app_flutter/$f" > "s22_r2_$f" 2>/dev/null; done
   python -c "import sqlite3;c=sqlite3.connect('s22_r2_ctt_local.db');\
print('total=',c.execute('SELECT COUNT(*) FROM sync_pendientes').fetchone()[0]);\
[print(r) for r in c.execute('SELECT secuencia,id,estado,entidad_id,creado_en_dispositivo FROM sync_pendientes ORDER BY secuencia')]"
   ```
   **Esperado:** 2–3 filas con `estado='pendiente'` (o `enviando`), una por cambio.
   **Dónde mirar:** tabla `sync_pendientes` (columnas `secuencia,id,estado,entidad_id`).
4. **[VOS]** Reinstalar el **mismo** build conservando datos:
   ```
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```
5. **[VOS]** Volver a leer la cola:
   ```
   adb exec-out run-as cl.ctt.ctt_mobile sh -c 'cat app_flutter/ctt_local.db' > s22_r2b.db
   python -c "import sqlite3;c=sqlite3.connect('s22_r2b.db');\
print('user_version=',c.execute('PRAGMA user_version').fetchone()[0]);\
print('total=',c.execute('SELECT COUNT(*) FROM sync_pendientes').fetchone()[0]);\
[print(r) for r in c.execute('SELECT secuencia,id,estado,entidad_id FROM sync_pendientes ORDER BY secuencia')]"
   ```

**Esperado:** exactamente las **mismas** filas que en el paso 3 (igual `secuencia`, `id`,
`estado`, `entidad_id`), `user_version = 6`. **Dónde mirar:** `sync_pendientes`.
**Criterio fallido:** si falta alguna fila o cambió su `id`/`secuencia`.

---

## R3 — Exclusión de backup (fase 6)

> Prueba que `app_flutter/` (base + respaldos + export) y las SharedPreferences de
> secure storage están excluidas de Auto Backup. Config: `backup_rules.xml` +
> `data_extraction_rules.xml`, cableadas en el manifest.
> **R3 desinstala por completo la app → la cola se pierde a propósito.** R4 la vuelve a
> crear.

1. **[VOS]** Con filas en la cola (de R2), habilitar backup y forzarlo:
   ```
   adb shell bmgr enabled
   adb shell bmgr enable true
   adb shell bmgr backupnow cl.ctt.ctt_mobile
   ```
   **Esperado:** `Backup finished with result: Success` para el paquete.
   **Dónde mirar:** salida de `backupnow`.
2. **[VOS]** Desinstalar por completo (sin `-k`):
   ```
   adb uninstall cl.ctt.ctt_mobile
   ```
3. **[VOS]** Reinstalar y restaurar según el mecanismo de Android:
   ```
   adb install build/app/outputs/flutter-apk/app-debug.apk
   adb shell bmgr autorestore true
   # Forzar restore del último set si no fue automático:
   adb shell dumpsys backup | grep -A3 "Ancestral\|Current"   # ubicar el token
   adb shell bmgr restore <TOKEN> cl.ctt.ctt_mobile
   ```
4. **[VOS]** Verificar que la base NO volvió:
   ```
   adb exec-out run-as cl.ctt.ctt_mobile sh -c 'ls -l app_flutter/ 2>/dev/null || echo "sin app_flutter"'
   ```
   Y si `ctt_local.db` existiera, confirmar que está vacía:
   ```
   adb exec-out run-as cl.ctt.ctt_mobile sh -c 'cat app_flutter/ctt_local.db' > s22_r3.db 2>/dev/null && \
   python -c "import sqlite3;c=sqlite3.connect('s22_r3.db');print('total=',c.execute('SELECT COUNT(*) FROM sync_pendientes').fetchone()[0])" || echo "no hay base"
   ```

**Esperado:** `app_flutter/ctt_local.db` **no existe** (o la app arranca sin cola: 0 filas).
Secundario: Luis aparece **deslogueado** (secure storage tampoco se restauró).
**Dónde mirar:** `ls app_flutter/`, conteo de `sync_pendientes`, pantalla de login.
**CRITERIO FALLIDO:** si la base vuelve con las filas previas → las reglas de exclusión
no funcionan.

---

## R4 — Rescate de punta a punta

### Paso 0 — Preparar el servidor (una sola vez) · dry-run ctt_dev

1. **[VOS]** Ver en qué revisión está ctt_dev y el dry-run de la migración:
   ```
   cd ctt-backend
   python -m alembic current
   python -m alembic upgrade head --sql    # dry-run: muestra el DDL de cola_rescate
   ```
2. **[KALD]** Aprobar el dry-run (regla: ningún cambio en ctt_dev sin OK de Kald).
3. **[VOS]** Aplicar:
   ```
   python -m alembic upgrade head
   python -m alembic current               # debe quedar en 522cc1d85034 (head)
   ```
   **Esperado:** `cola_rescate` existe en ctt_dev. **Dónde mirar:** `alembic current` = head.

### Paso 1 — Repoblar la cola (R3 la borró)

4. **[KALD]** Reabrir la app, loguear como Luis, modo avión, hacer **2–3 cambios**.
5. **[VOS]** Confirmar la cola (como en R2 paso 3). Anotar cuántas filas no terminales (N).

### Paso 2 — Forzar la pantalla de recuperación (user_version = 7)

6. **[VOS]** Parar la app y sacar la base (con WAL/SHM):
   ```
   adb shell am force-stop cl.ctt.ctt_mobile
   for f in ctt_local.db ctt_local.db-wal ctt_local.db-shm; do \
     adb exec-out run-as cl.ctt.ctt_mobile sh -c "cat app_flutter/$f" > "$f" 2>/dev/null; done
   ```
7. **[VOS]** Consolidar WAL y subir la versión a 7 en el PC:
   ```
   python -c "import sqlite3;c=sqlite3.connect('ctt_local.db');c.execute('PRAGMA wal_checkpoint(TRUNCATE)');c.execute('PRAGMA user_version=7');c.commit();c.close();print('ok v7')"
   ```
8. **[VOS]** Devolver la base y borrar los WAL/SHM viejos del dispositivo (para que no
   pisen el cambio):
   ```
   adb push ctt_local.db /data/local/tmp/ctt_push.db
   adb shell run-as cl.ctt.ctt_mobile cp /data/local/tmp/ctt_push.db app_flutter/ctt_local.db
   adb shell run-as cl.ctt.ctt_mobile rm -f app_flutter/ctt_local.db-wal app_flutter/ctt_local.db-shm
   adb shell rm /data/local/tmp/ctt_push.db
   ```
9. **[KALD]** Desactivar modo avión (hace falta red para el rescate) y abrir la app.

**Esperado (cliente):** aparece la **pantalla de recuperación** con el conteo
("Tenés N cambios guardados…") y dispara el rescate automático; al terminar muestra
"tus cambios se enviaron a tu supervisor" (o el parcial si hubo rechazos).
**Dónde mirar:** pantalla del teléfono.

### Paso 3 — Verificar en el servidor

10. **[VOS]** En el host del backend, contra la base ctt_dev. Usar la
    `DATABASE_URL` configurada del backend (no incrustar credenciales acá); p. ej.
    `export PGSERVICE=...` o `psql "$DATABASE_URL"`:
    ```
    psql "$DATABASE_URL" -c \
      "SELECT idempotency_key, estado_revision, subido_por_tercero, instalacion_id \
         FROM cola_rescate ORDER BY recibido_at;"
    psql "$DATABASE_URL" -c \
      "SELECT a.accion, a.entidad_tipo, a.entidad_id, a.synced_offline, \
              a.metadata->>'idempotency_key' AS idem, a.metadata->>'estado_revision' AS estado, \
              u.nombre_completo AS subio \
         FROM audit_log a JOIN usuarios u ON u.id = a.actor_id \
        WHERE a.accion='rescate_cola' ORDER BY a.created_at;"
    ```

**Esperado:**
- `cola_rescate`: **N filas** (una por fila no terminal), `estado_revision='pendiente_revision'`
  (sería `ya_aplicada` solo si ese `idempotency_key` ya se hubiera completado en CTT-105),
  `subido_por_tercero = false` (Luis sube lo suyo). **Dónde mirar:** tabla `cola_rescate`.
- `audit_log`: N filas con `accion='rescate_cola'`, `synced_offline = true`, `subio = 'Luis Fuentes'`,
  cada una con su `idempotency_key`. **Dónde mirar:** tabla `audit_log` (`metadata` JSON).

### Paso 4 — Restaurar y confirmar que la app vuelve a abrir

11. **[VOS]** Bajar de nuevo la base, volver a `user_version = 6` y devolverla:
    ```
    adb shell am force-stop cl.ctt.ctt_mobile
    adb exec-out run-as cl.ctt.ctt_mobile sh -c 'cat app_flutter/ctt_local.db' > ctt_local.db
    python -c "import sqlite3;c=sqlite3.connect('ctt_local.db');c.execute('PRAGMA user_version=6');c.commit();c.close();print('ok v6')"
    adb push ctt_local.db /data/local/tmp/ctt_push.db
    adb shell run-as cl.ctt.ctt_mobile cp /data/local/tmp/ctt_push.db app_flutter/ctt_local.db
    adb shell run-as cl.ctt.ctt_mobile rm -f app_flutter/ctt_local.db-wal app_flutter/ctt_local.db-shm
    adb shell rm /data/local/tmp/ctt_push.db
    ```
12. **[KALD]** Abrir la app.
13. **[VOS]** Confirmar que la cola local sigue intacta (el rescate NO borra la cola, solo
    lee):
    ```
    adb exec-out run-as cl.ctt.ctt_mobile sh -c 'cat app_flutter/ctt_local.db' > s22_r4_final.db
    python -c "import sqlite3;c=sqlite3.connect('s22_r4_final.db');\
print('user_version=',c.execute('PRAGMA user_version').fetchone()[0]);\
print('total=',c.execute('SELECT COUNT(*) FROM sync_pendientes').fetchone()[0])"
    ```

**Esperado:** la app abre **normal** (pantalla principal, no recuperación);
`user_version = 6`; `sync_pendientes` conserva las N filas. **Dónde mirar:** pantalla +
`sync_pendientes`.

---

## Notas / riesgos

- **run-as requiere build debug.** Un release no es debuggable y los pasos de SQL fallan.
- **WAL:** siempre sacar/devolver `-wal` y `-shm`, o consolidar con `wal_checkpoint(TRUNCATE)`
  antes de editar `user_version`; si no, un WAL viejo puede pisar el cambio al reabrir.
- **R3 destruye la cola** (desinstalación completa). R4 la repuebla en su Paso 1.
- **Transporte de backup (R3):** si el S22 usa el transporte de Google, el backup/restore
  puede tardar o depender de la cuenta. Alternativa: transporte local
  (`adb shell bmgr transport com.android.localtransport/.LocalTransport` si está disponible)
  para una prueba determinística en el dispositivo.
- **ctt_dev:** aplicar `522cc1d85034` es DDL sobre ctt_dev → dry-run + OK de Kald primero.
