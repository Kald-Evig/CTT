# CTT Mobile

App Flutter *offline-first* para supervisión de trabajadores en terreno en obras de construcción (Chile).

## Stack

| Capa | Tecnología |
|------|-----------|
| Estado global | Riverpod 2.x |
| Base de datos local | Drift (SQLite) |
| HTTP | Dio 5.x |
| Auth | Firebase Auth |
| Monitoreo de errores | Firebase Crashlytics |
| Sync en background | WorkManager |
| Navegación | GoRouter |

---

## Setup inicial (primera vez)

### 1. Instalar Flutter

```powershell
# Descargar Flutter SDK: https://docs.flutter.dev/get-started/install/windows
# Agregar al PATH: C:\flutter\bin
flutter --version   # debe mostrar 3.22+
```

### 2. Correr el script de bootstrap

```powershell
cd D:\VSCode\CTT\ctt-mobile
.\setup.ps1
```

El script:
1. Genera el boilerplate Android con `flutter create`
2. Instala dependencias con `flutter pub get`
3. Genera código con `build_runner` (Drift, Riverpod, Freezed)

### 3. Configurar Firebase

```powershell
dart pub global activate flutterfire_cli
flutterfire configure --project=<tu-proyecto-firebase>
```

Esto genera `lib/firebase_options.dart` y `android/app/google-services.json`.
**Nunca commitear `google-services.json` — está en `.gitignore`.**

---

## Ejecutar la app

### Debug (solo desarrollo — NO medir performance aquí)

```powershell
flutter run
```

> **IMPORTANTE: NUNCA medir performance en debug build.**
> El compilador JIT de debug tiene overhead de 2-5x vs release.
> Las animaciones, tiempos de respuesta y uso de memoria en debug NO representan el comportamiento real.

### Profile (para medir performance)

```powershell
flutter run --profile
```

Usa el compilador AOT igual que release, pero con el profiler habilitado.
Usar siempre `--profile` para medir FPS, memoria y tiempo de startup.

### Release (distribución)

```powershell
flutter build apk --release
# o para bundle de Play Store:
flutter build appbundle --release
```

---

## Conectar Samsung S22 por USB

1. En el S22: **Ajustes → Acerca del teléfono → Información del software** → tocar **"Número de compilación"** 7 veces (activa opciones de desarrollador).
2. **Ajustes → Opciones de desarrollador** → activar **"Depuración USB"**.
3. Conectar el cable USB.
4. En la pantalla del S22: aceptar el diálogo "¿Permitir depuración USB?".
5. Verificar que el dispositivo aparece:
   ```powershell
   flutter devices
   # Debe mostrar algo como: SM-S901B (mobile) • RFXXXXXXXX • android-arm64
   ```
6. Ejecutar:
   ```powershell
   flutter run --profile   # en S22 físico, siempre profile para medir real
   ```

---

## Generar código (Drift + Riverpod + Freezed)

```powershell
dart run build_runner build --delete-conflicting-outputs
```

Para modo watch durante desarrollo:

```powershell
dart run build_runner watch --delete-conflicting-outputs
```

---

## Variables de entorno

Configurar con `--dart-define` al ejecutar o compilar. **Nunca en el código fuente.**

| Variable | Descripción | Default |
|----------|-------------|---------|
| `API_BASE_URL` | URL base de la API backend | `http://10.0.2.2:8000` (emulador) |

Ejemplo:
```powershell
flutter run --dart-define=API_BASE_URL=https://api.ctt.cl
flutter build apk --release --dart-define=API_BASE_URL=https://api.ctt.cl
```

Para el S22 físico en desarrollo local, usar la IP del PC en la red local:
```powershell
flutter run --profile --dart-define=API_BASE_URL=http://192.168.1.x:8000
```

---

## Estructura del proyecto

```
lib/
  core/
    config/       # Entorno y configuración
    errors/       # Failures y Exceptions tipadas
    network/      # DioClient + interceptores
    security/     # SecureStorageService (JWT, empresa)
    sync/         # SyncService (WorkManager) + SyncQueue
    utils/        # Extensiones y helpers
  data/
    local/        # Base de datos Drift (database.dart + DAOs)
    remote/       # DataSources por entidad
    models/       # Modelos generados por Drift
    repositories/ # Implementaciones de repositorios
  domain/
    entities/     # Entidades de dominio puras
    repositories/ # Interfaces (abstracts)
    enums/        # Enums espejo del backend (enums_ctt.dart)
  presentation/
    auth/         # Pantalla de login
    trabajador/   # UI del trabajador
    residente/    # UI del residente
    coordinador/  # UI del coordinador
    admin/        # UI del administrador
    shared/       # Widgets reutilizables
  app.dart        # GoRouter + MaterialApp
  main.dart       # Inicialización y error handling
```

---

## Backend

El backend FastAPI está en `D:\VSCode\CTT\ctt-backend\`.
Para desarrollo local, levantarlo antes de correr la app:

```powershell
cd D:\VSCode\CTT\ctt-backend
.\run.sh   # o: uvicorn app.main:app --reload
# API disponible en http://127.0.0.1:8000
# Emulador Android accede como: http://10.0.2.2:8000
```

---

## Tests

```powershell
flutter test
```

Los tests en `test/enums_ctt_test.dart` verifican que los valores de los enums
del dominio coincidan exactamente con los del backend (`app/enums.py`).
Si el backend cambia un valor de enum, el test falla inmediatamente.
