# Runbook — Sesión de runtime S22 · CTT-103 + CTT-127

**Objetivo:** validar en el S22 real lo que los tests no pueden: (R1) la migración v6→v7
con cola poblada, (R2) sin red → la fila sale apenas vuelve la señal y la nube se apaga
sin salir de la pantalla, (R3) rechazo determinista de punta a punta (dead-letter en el
servidor + chip en el teléfono), (R4) conflicto con orden por ítem y reconciliación,
(R5) huérfana en `enviando` recuperada por lease (CTT-127).

> **NO ejecutar nada en el teléfono hasta que Kald confirme que está conectado**
> (`adb devices` lo lista). **NO hacer `pm clear` en este runbook:** R1 necesita la
> base v6 existente para probar la migración real.
> **El backend en `AUTH_MODE=mock` no se deja corriendo sin nadie mirando.**

## Convenciones

- **[KALD]** = acción física en el teléfono o decisión. **[VOS]** = comando del agente.
- Mismas convenciones de lectura de la base que `runbook_s22_ctt130_fase4b.md`
  (`run-as` + Python `sqlite3`, sacar `-wal`/`-shm` o hacer `wal_checkpoint`).
- Helper de lectura de la cola (usar en cada paso que diga "leer la cola"):
  ```
  for f in ctt_local.db ctt_local.db-wal ctt_local.db-shm; do \
    adb exec-out run-as cl.ctt.ctt_mobile sh -c "cat app_flutter/$f" > "q_$f" 2>/dev/null; done
  python -c "import sqlite3;c=sqlite3.connect('q_ctt_local.db');\
  print('user_version=',c.execute('PRAGMA user_version').fetchone()[0]);\
  [print(r) for r in c.execute('SELECT secuencia,substr(id,1,8),substr(entidad_id,1,8),estado,motivo,intentos_red,intentos_servidor,ultimo_error_codigo,proximo_intento_en,tomado_por IS NOT NULL,tomado_hasta,conflicto_id,rechazo_id FROM sync_pendientes ORDER BY secuencia')]"
  ```
- Tokens mock (Bearer = firebase_uid): Luis `pCcukEA7BfP4SiOAZNaeSkxAHY32`,
  Jorge (Coordinador) `on1QBkdHBSZikDjR47io0M3mAVD3`.
- Estados de `sync_pendientes` desde v7: no terminales `pendiente`, `enviando`,
  `esperando_resolucion`; terminales `sincronizado`, `rechazada`, `en_revision`
  (y `descartado` solo para "ganó el servidor" y filas viejas).

## Prerrequisitos

1. **[KALD]** S22 conectado (`adb devices`) y `<TAILNET_URL>` del backend.
2. **[VOS]** Backend en `feature/mvp-sync` HEAD, `ENV=local AUTH_MODE=mock`.
   `alembic current` = `7f3a9c2e1b84` (sync_rechazos; ya aplicada el 4-oct).
3. **[VOS]** Preparar **cuatro** ítems de Luis en `abierto` en el mismo proyecto
   (`<ITEM_A>`..`<ITEM_D>`) y el id de **Marcos Díaz** (`<ID_MARCOS>`, trabajador miembro).
   Hacen falta 4 porque el trabajador solo tiene 2 transiciones por ítem
   (`abierto→en_progreso`, `en_progreso→pendiente_revision`; state_machine.py:43-63): un
   ítem reusado entre secciones queda en `pendiente_revision` y Luis ya no puede moverlo.
   Reparto: **A** → R1+R2 (2 cambios) · **B** → R1+R2 (1 cambio) y R3 · **C** → R4 ·
   **D** → R5. Se crean por la API como Jorge (coordinador_principal de 4ec74662), que
   nacen en `abierto`:
   ```
   # ×4, nombres "CTT-103 RT A/B/C/D"
   curl -s -X POST <TAILNET_URL>/items -H "Authorization: Bearer on1QBkdHBSZikDjR47io0M3mAVD3" \
     -H "Content-Type: application/json" \
     -d '{"proyecto_id":"4ec74662-abdb-4b9a-b606-960299144e50","nombre":"CTT-103 RT A","asignado_a":"43c8297a-ab65-4ef7-a6a9-e93d148feb24"}'
   ```
   `<ID_MARCOS>` = `97e2f903-175e-4b72-a914-f1fe81eca679` (miembro trabajador activo de 4ec74662).
   Guardar los ids en `.evidencia/ctt103_rt_fase0_items.txt`.
4. **[VOS]** Build debug del HEAD (v7) listo pero **sin instalar todavía**:
   ```
   cd ctt-mobile
   flutter build apk --debug --dart-define=API_BASE_URL=<TAILNET_URL> --dart-define=AUTH_MODE=mock
   ```
   Registrar el SHA-256 del APK (la verificación de build es por hash, no por versionName).

---

## R1 — Migración v6→v7 con cola poblada (sin perder nada)

1. **[VOS]** Leer la cola: confirmar `user_version = 6` (app vieja instalada).
2. **[KALD]** Modo avión. Con la app VIEJA, hacer **2 cambios de estado** en `<ITEM_A>`
   (p. ej. abierto→en_progreso y en_progreso→pendiente_revision) y **1** en `<ITEM_B>`.
   Hacerlo rápido: la app vieja todavía descarta tras 5 fallos de red de WorkManager.
3. **[VOS]** Leer la cola. **Esperado:** 3 filas `pendiente`, secuencias consecutivas.
   Guardar la salida como evidencia "antes".
4. **[VOS]** Instalar el APK nuevo **encima** (sin desinstalar):
   `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
5. **[KALD]** Abrir la app (sigue en modo avión). No debe aparecer la pantalla de recuperación.
6. **[VOS]** Leer la cola. **Esperado:** `user_version = 7`; las mismas 3 filas, mismos
   ids, secuencias, payload y estado `pendiente`; columna `rechazo_id` presente y NULL.
   **Dónde mirar:** comparar contra la salida del paso 3.

## R2 — Sin red → sale apenas vuelve la señal; la nube se apaga sola

Continúa de R1 (3 filas pendientes, modo avión).

1. **[KALD]** Con la app en la lista "Mis ítems", observar: `<ITEM_A>` y `<ITEM_B>` con la
   nube naranja.
2. **[KALD]** Esperar a que WorkManager corra al menos una vez en modo avión (o tocar algo
   que dispare el ciclo). **[VOS]** Leer la cola. **Esperado:** filas siguen `pendiente`,
   `intentos_red ≥ 1`, `ultimo_error_codigo` NULL, `proximo_intento_en` con fecha futura.
   **Ninguna `descartado`.**
3. **[KALD]** **Sin salir de la pantalla "Mis ítems"**, desactivar modo avión.
4. **Esperado (sin re-entrar a la pantalla):** en segundos, la nube de `<ITEM_B>` se apaga.
   `<ITEM_A>` envía sus 2 filas **en orden** (la 2ª solo después de la 1ª).
   **Dónde mirar:** pantalla + leer la cola (`sincronizado` en las 3, en orden de secuencia)
   + en ctt_dev el estado final de los ítems.
   Si la nube NO se apaga sin salir y volver → falla de D6-R (reactividad). Registrar.

## R3 — Rechazo determinista de punta a punta

1. **[KALD]** Modo avión. Hacer **1** cambio de estado en `<ITEM_B>` (tras R2 quedó en
   `en_progreso`, así que el cambio válido es `en_progreso→pendiente_revision`).
2. **[VOS]** Reasignar `<ITEM_B>` a Marcos con el token de Jorge:
   ```
   curl -s -X POST <TAILNET_URL>/items/<ITEM_B>/asignar \
     -H "Authorization: Bearer on1QBkdHBSZikDjR47io0M3mAVD3" \
     -H "Content-Type: application/json" -d '{"usuario_id":"<ID_MARCOS>"}'
   ```
3. **[KALD]** Desactivar modo avión, quedarse en "Mis ítems".
4. **[VOS]** Leer la cola. **Esperado:** la fila en `rechazada`, con `rechazo_id` no nulo y
   `ultimo_error` = `no_autorizado: ...`. **Nunca `descartado`.**
5. **[VOS]** En ctt_dev:
   ```
   psql ... -c "SELECT id,usuario_id,entidad_id,codigo_http,motivo,estado_resolucion,creado_at FROM sync_rechazos ORDER BY creado_at DESC LIMIT 3;"
   ```
   **Esperado:** 1 fila, `codigo_http=403`, `motivo=no_autorizado`, `estado_resolucion=pendiente`,
   su `id` = el `rechazo_id` del teléfono. (Esto prueba de punta a punta el header
   `X-Sync-Origen: cola` del Dio de sync.)
6. **[KALD]** **Esperado en pantalla:** el ítem **sigue visible** en "Mis ítems" con el chip
   marrón "Envío rechazado — lo revisa coordinación", sin acciones. El pull de Mis ítems es
   upsert-only (no borra lo que el server ya no devuelve — items_repository.dart:55-66) y la
   lista sale de `obtenerAsignadosA` filtrando el cache LOCAL, que conserva `asignado_a=Luis`
   (stale). Por eso la reasignación a Marcos NO lo saca de la lista del S22. Si desapareciera,
   es una regresión del pull (no de la cola): anotarlo y PARAR.
   (`<ITEM_B>` queda asignado a Marcos; no se revierte — R4 y R5 usan `<ITEM_C>`/`<ITEM_D>`.)

## R4 — Conflicto, orden por ítem y reconciliación

1. **[KALD]** Modo avión. Hacer **2** cambios de estado seguidos en `<ITEM_C>` (fila X y fila Y:
   `abierto→en_progreso` y `en_progreso→pendiente_revision`).
2. **[VOS]** Provocar el conflicto: editar el ítem desde el servidor (Jorge) sin cambiar
   la asignación. `PUT /items/<ITEM_C>` bumpea `Item.updated_at` (`onupdate=_now`) **solo si
   el body cambia de verdad algún campo** (`editar_item` arma un diff y retorna sin commit si
   nada cambió — verificado en items.py:352-361). Por eso mandamos una `descripcion` nueva:
   ```
   curl -s -X PUT <TAILNET_URL>/items/<ITEM_C> \
     -H "Authorization: Bearer on1QBkdHBSZikDjR47io0M3mAVD3" \
     -H "Content-Type: application/json" \
     -d '{"descripcion":"conflicto R4 <marca_de_tiempo_unica>"}'
   ```
   La detección de conflicto compara `item.updated_at > device_timestamp` (items.py:530): el
   edit de Jorge ocurre DESPUÉS de los cambios offline, así que su `updated_at` queda posterior.
3. **[KALD]** Desactivar modo avión.
4. **[VOS]** Leer la cola. **Esperado:** X en `esperando_resolucion` con `conflicto_id`;
   **Y sigue `pendiente` y NO se envió** (orden por ítem: el conflicto bloquea las siguientes).
   En ctt_dev: `SELECT id FROM sync_conflictos ORDER BY created_at DESC LIMIT 2;` → **1** conflicto nuevo
   (no 2: sin duplicado, CTT-136).
5. **[VOS]** Resolver con Jorge:
   `curl -s -X POST <TAILNET_URL>/sync/conflictos/<CONFLICTO_ID>/resolver -H "Authorization: Bearer on1QBkdHBSZikDjR47io0M3mAVD3" -H "Content-Type: application/json" -d '{"version_ganadora":"servidor"}'`
6. **[KALD]** Llevar la app a segundo plano y volver (dispara la reconciliación).
7. **[VOS]** Leer la cola. **Esperado:** X en `descartado` / `conflicto_resuelto_servidor`;
   **ahora Y se envía y vuelve en `esperando_resolucion` con un `conflicto_id` NUEVO** (≠ el de X).
   > **Conflicto en cascada — es CTT-143 (autoconflicto por cambios offline al mismo ítem).**
   > Causa: al sincronizar X se bumpea `C.updated_at`; Y lleva un `device_timestamp` anterior,
   > así que al desbloquearse y enviarse cumple `updated_at > device_timestamp` (items.py:530)
   > → 409 con conflicto nuevo. NO es por "el resolver no toca `updated_at`": pasa igual sin la
   > edición de Jorge, por el solo hecho de dos cambios offline secuenciales al mismo ítem.
   > Que Y re-conflictúe (en vez de quedar trabada o descartarse) prueba que el orden por ítem
   > la liberó y re-evaluó; el 409 en sí es CTT-143.
8. **[VOS]** Resolver ese segundo conflicto con Jorge (mismo curl del paso 5, con el nuevo
   `<CONFLICTO_ID>`). **Verificación final:** ninguna fila de `<ITEM_C>` en estado no terminal
   y **ninguna** fila con `tomado_por` distinto de NULL.

## R5 — Huérfana en `enviando` recuperada por lease (CTT-127)

Simula que el ciclo muere a mitad del POST.

1. **[KALD]** Bloquear el puerto del backend en el PC para que las conexiones **cuelguen**
   (no rechazar). `New-NetFirewallRule` requiere elevación y el agente NO corre elevado
   (verificado: `IsInRole(Administrator)` = False), así que Kald lo corre en una **PowerShell
   de administrador**:
   `New-NetFirewallRule -DisplayName ctt-block -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Block`
   El Action=Block de Windows Firewall descarta los SYN en silencio (sin RST) → el cliente ve
   timeout de conexión, no rechazo inmediato. **[VOS]** Verificarlo con un curl desde otro
   equipo del tailnet antes de seguir (debe colgar hasta timeout, no responder al instante).
2. **[KALD]** Con red, hacer **1** cambio de estado en `<ITEM_D>` (`abierto→en_progreso`).
3. **[VOS]** Dentro de los ~30 s: `adb shell am force-stop cl.ctt.ctt_mobile`.
4. **[VOS]** Leer la cola. **Esperado:** la fila en `enviando`, con `tomado_por` y
   `tomado_hasta` ≈ instante del reclamo + 90 s.
5. **[KALD]** Quitar el bloqueo (PowerShell de administrador, misma razón que el paso 1):
   `Remove-NetFirewallRule -DisplayName ctt-block`.
   **[VOS]** Confirmar que ya no existe con `Get-NetFirewallRule -DisplayName ctt-block`
   (la lectura sí la puede hacer el agente sin elevación).
6. **[KALD]** Abrir la app **antes** de que venza el lease. **[VOS]** Leer la cola.
   **Esperado:** sigue `enviando` (lease vigente: no se retoma todavía).
7. **[KALD]** Esperar > 90 s desde el paso 4 y forzar un ciclo (segundo plano y volver, o
   cambiar conectividad). **[VOS]** Leer la cola. **Esperado:** `sincronizado`, misma
   `idempotency_key`. En ctt_dev, el ítem en el estado pedido y **una sola** transición
   en `item_historial` para esa clave.

---

## No cubierto en runtime (cubierto por tests; anotar si se quiere forzar)

- **5xx/408/429 en el camino online (C6) y Retry-After:** requiere que el backend devuelva
  esos códigos a voluntad; tests de `transicion_c6_test` y `clasificador_ciclo_test`.
- **401 → pausa:** en modo mock el token no vence. Se valida con Firebase real (CTT-88).
- **Tope de 6 `intentos_servidor` → rescate → `en_revision` (D5):** `rescate_tope_test`.
- **Isolate headless escribiendo con la app en primer plano:** límite documentado de D6-R2.

## Estado al pausar (2026-10-06)

Runtime pausado hasta mañana. R0 (Fase 0) y R1 completos; R2 suspendido por el
hallazgo del drenado (ya corregido en código).

**Código (pusheado a `feature/mvp-sync`):**
- `a340c26` — el ciclo drena toda la cola elegible por corrida (re-consulta
  `filasReclamables` con conjunto `intentados`, tope 50) + sella `sincronizado_en` y
  `ultimo_intento_en`. 5 tests (`ciclo_multipasada_test`).
- `dd2a92b` — backoff y Retry-After medidos desde `finIntento` (respuesta), no desde el
  reclamo. +1 test (f). Suite: 146 passed.

**APK de runtime:** construido con `API_BASE_URL=http://192.168.1.12:8000` +
`AUTH_MODE=mock`, SHA-256 `f31a3aaab7a0deaa150ea1dabd5f269947ddbf0897d78d84a561dbe6acec6d16`.
**NO instalado** (el S22 sigue con el APK del tailnet, v7). `.evidencia/ctt103_rt_apk_lan_sha256.txt`.

**`network_security_config.xml`:** tiene agregada la IP LAN `192.168.1.12` (cleartext),
**sin commitear a propósito** (debilitaría CTT-106). Se reutiliza mañana; revertir al
cerrar el runtime.

**Cola del S22 (post-R1/R2 parcial):** `sec 1,2` sincronizado (viejas); `sec 3`
(A→en_progreso) sincronizado; `sec 4` (A→pendiente_revision) en **`esperando_resolucion`**
(`conflicto_id` 3ca5582d, 409): la envió una corrida **headless del APK VIEJO** el 2026-10-06
~20:39 (`tomado_por …:headless:…`, distinto al de sec 3) y conflictó por **CTT-143** (sec 3
bumpeó `A.updated_at` por encima del `device_timestamp` de sec 4). NO es el bug multipass —
ese todavía NO se ejerció en el dispositivo; lo prueba R2b/E. `sec 5` (B→en_progreso)
sincronizado. En ctt_dev: A=`en_progreso`, B=`en_progreso`. Ítems de runtime:
A=`7e52df00`, B=`70e35c62`, C=`4cbf8c5e`, D=`70f80fec`; `<ID_MARCOS>`=`97e2f903…`.

**CTT-143 (nuevo):** autoconflicto por dos cambios offline al MISMO ítem — `items.py:530`.
La 1ª fila sincroniza y bumpea `updated_at`; la 2ª (con `device_timestamp` anterior) cae en
409/`esperando_resolucion` contra el **propio** cambio del dispositivo (falso positivo). Afecta
`sec 4` y la fila `E2` de R2b. Pendiente de diseño; no se arregla en esta sesión.

**CTT-141 (nuevo):** la nube NO se apaga en segundos al reconectar. El flush por flanco
offline→online dispara en el instante del avión-OFF, cuando el Wi-Fi todavía re-asocia; los
POST fallan por red (`SocketException: Software caused connection abort, errno 103`) y, como
no hay re-intento pronto (solo próximo flanco o WorkManager ~15 min), la nube queda colgada.
En R2b drenó recién a las ~11:44 por **WorkManager** (no por el flanco). Reproducible. No se
arregla en esta sesión.
- **`resume` NO dispara el flush** (`app.dart:301-307`): al volver a primer plano solo notifica
  a la UI (`notificarSyncPendientesExterno`) y reconcilia conflictos (`_reconciliar`), no corre
  el ciclo de push. Parte de CTT-141 — por eso un simple resume no drena la cola.
- **`cmd jobscheduler run -f` NO fuerza el periódico**: WorkManager lo rechaza ("executed before
  schedule … rescheduling for later"). El disparo manual que SÍ funciona es un **arranque en frío**
  (cerrar desde Recientes y reabrir), que corre el ciclo foreground.

**Resultado R2b (aceptado):**
- **a340c26 PASA** en el dispositivo: la fila con `200` (sec 6) y la fila con `409` (sec 7)
  tienen el **mismo `tomado_por`** (`…:headless:1de7d79e…`) y `ultimo_intento_en` en orden →
  una sola corrida drenó ambas (CTT-143 en E2).
- **"La nube en segundos" FALLA** por **CTT-141** (documentado arriba).
- **Reactividad de UI: PENDIENTE** de lo que observó Kald (no se pudo aislar porque el flush
  no completó por CTT-141).

**DESVIACIÓN:** el backend en `AUTH_MODE=mock` quedó corriendo **sin supervisión
continua** desde las ~14:26 hasta las ~23:46 (hora local), incluyendo la ventana
18:08–23:41. Detenido al pausar (puerto 8000 libre, confirmado). Para la próxima sesión:
no dejar el mock arriba fuera de la ventana activa.

**Pasos para retomar (mañana):**
1. **[KALD, admin]** crear la regla:
   `New-NetFirewallRule -DisplayName ctt-8000-s22 -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow -Profile Public -RemoteAddress 192.168.1.4`
2. **[KALD, S22]** desactivar Tailscale.
3. **[VOS]** levantar uvicorn (`0.0.0.0:8000`, mock) y verificar que el S22 llega:
   `adb shell` → `curl http://192.168.1.12:8000/health`. Guardar evidencia.
4. **[VOS]** instalar el APK `f31a3aaa…` encima (sin `pm clear`); confirmar `user_version=7`
   y cola intacta (incluida `sec 4` en `esperando_resolucion` — CTT-143).
5. **[VOS/KALD]** correr **R2** con la red local (nube de un ítem que se apaga al reconectar).
   Cierre: `Remove-NetFirewallRule -DisplayName ctt-8000-s22`, revertir
   `network_security_config.xml`, bajar el backend.

---

## Al terminar

- **[VOS]** Bajar el backend (`AUTH_MODE=mock` no queda corriendo).
- **[VOS]** Confirmar que la regla de firewall `ctt-block` no existe.
- **[KALD]** Confirmar el transporte de backup del S22 en el de Google (regla de la sesión CTT-130).
- Pegar las lecturas de la cola y las consultas de ctt_dev **crudas** en el reporte, una por paso.
