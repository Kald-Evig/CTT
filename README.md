# CTT — Field Service Management

Plataforma *offline-first* de gestión de trabajadores en terreno para obras de construcción en Chile.

| Componente | Stack | Estado |
|---|---|---|
| **Backend** (`ctt-backend/`) | FastAPI · SQLAlchemy 2 · SQLite (dev) | ✅ MVP operativo |
| **App móvil** (`ctt-mobile/`) | Flutter 3.44 · Riverpod · Firebase Auth | ✅ Auth + navegación por rol |
| **Frontend web** (`frontend/`) | HTML + JS plano (cliente de revisión E2E) | ✅ Solo para demo |

---

## Requisitos generales

- **Git**
- **Python 3.11+** (para el backend)
- **Flutter 3.44.2+** (para la app móvil)
- **Android SDK** con un emulador API 33+ (o dispositivo físico)
- **Java 17** (requerido por el toolchain de Android)

---

## 1. Backend

### Instalación y arranque

```bash
cd ctt-backend
./run.sh
```

`run.sh` crea el entorno virtual, instala dependencias, siembra la base de datos y levanta el servidor en `http://127.0.0.1:8000`.

**Arranque manual equivalente:**

```bash
cd ctt-backend
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python -m app.seed               # crea ctt_dev.db con datos de demo
uvicorn app.main:app --reload
```

### Endpoints útiles

| URL | Descripción |
|-----|-------------|
| `http://127.0.0.1:8000/docs` | Documentación interactiva Swagger |
| `http://127.0.0.1:8000/health` | Healthcheck |
| `GET /me` | Perfil del usuario autenticado + empresas activas |

### Tests

```bash
cd ctt-backend
.venv/Scripts/python -m pytest -v   # Windows
# o
python -m pytest -v                  # macOS/Linux
```

48 tests: máquina de estados, permisos, aislamiento multi-tenant, flujo operativo completo y endpoint `/me`.

### Autenticación en modo demo

El backend acepta `Authorization: Bearer <firebase_uid>` sin validación criptográfica (`AUTH_MODE=mock`). Para usuarios en múltiples empresas, agregar `X-Empresa-Id: <id>`.

| Bearer token | Persona | Rol |
|---|---|---|
| `uid-superadmin` | Soporte CTT | Super Admin (plataforma) |
| `uid-admin-a` | Patricia Reyes | Admin · Empresa A |
| `uid-coordinador-a` | Jorge Muñoz | Coordinador · Empresa A |
| `uid-residente-a` | Camila Soto | Residente · Empresa A |
| `uid-trabajador-1` | Luis Fuentes | Trabajador · Empresa A |
| `uid-trabajador-2` | Marcos Díaz | Trabajador · Empresa A |
| `uid-itinerante` | Rosa Carrasco | Trabajador en A / Residente en B (requiere `X-Empresa-Id`) |

```bash
curl http://127.0.0.1:8000/me \
  -H "Authorization: Bearer uid-coordinador-a"
```

---

## 2. App móvil (Flutter)

### Prerrequisitos adicionales

- Flutter 3.44.2 en el PATH (`flutter doctor` debe pasar)
- Un emulador Android corriendo, o dispositivo físico conectado con USB debugging activo
- El backend levantado en `http://127.0.0.1:8000`

### Configurar Firebase (primer setup)

El archivo `lib/firebase_options.dart` está excluido del repositorio (contiene claves de API). Hay dos opciones:

**Opción A — Recibir el archivo del equipo** (recomendado para colaboradores): pedir `firebase_options.dart` al autor y colocarlo en `ctt-mobile/lib/`.

**Opción B — Generar uno propio**:

```bash
# 1. Instalar FlutterFire CLI (una sola vez)
dart pub global activate flutterfire_cli

# 2. Autenticarse en Firebase con la cuenta del proyecto
firebase login

# 3. Configurar con el proyecto existente
cd ctt-mobile
flutterfire configure --project ctt-mobile-e031d --platforms android
```

Habilitar **Email/Password** como proveedor de autenticación en [Firebase Console](https://console.firebase.google.com) → Authentication → Sign-in methods.

### Generar código (build_runner)

Los archivos `.g.dart` (Riverpod, Drift, Freezed) están en `.gitignore`. Hay que generarlos una vez al clonar y cada vez que se modifiquen los archivos fuente con anotaciones:

```bash
cd ctt-mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Correr la app

```bash
cd ctt-mobile
flutter run
```

La app apunta por defecto a `http://10.0.2.2:8000` (dirección del host desde el emulador Android). Para apuntar a otro servidor:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000
```

### Tests

```bash
cd ctt-mobile
flutter test
```

### Usuario de prueba en Firebase

Crear manualmente en Firebase Console → Authentication → Users:

| Email | Contraseña |
|-------|-----------|
| `test@ctt.cl` | (definir al crear) |

> Este usuario de Firebase existe solo en el servicio de auth. Para que el móvil lo resuelva con `/me`, el backend también necesita un usuario con el mismo `firebase_uid`. En desarrollo, crear el usuario vía `POST /usuarios` con el UID que devuelve Firebase, o agregar la entrada directamente en `ctt_dev.db`.

---

## 3. Frontend web (cliente de revisión E2E)

Cliente HTML + JS plano para recorrer el flujo completo sin necesitar la app móvil. No requiere build.

```bash
cd frontend
python -m http.server 5500
# abrir http://127.0.0.1:5500
```

O abrir `frontend/index.html` directamente en el navegador (también funciona desde `file://`).

Usa los mismos tokens de la tabla de arriba. La interfaz se adapta al rol del token elegido.

---

## Flujo completo (backend + móvil)

```
1. cd ctt-backend && ./run.sh          # backend en :8000
2. Iniciar emulador Android
3. cd ctt-mobile && flutter run        # app en emulador
4. Login con test@ctt.cl
   → Firebase Auth valida credenciales
   → App llama GET /me con el UID como Bearer
   → Backend retorna perfil + empresa + rol
   → Router navega a la pantalla del rol
```

---

## Notas de build (Android)

El repositorio incluye configuraciones que resuelven incompatibilidades conocidas con Flutter 3.44+ y AGP 9:

| Archivo | Configuración | Motivo |
|---|---|---|
| `android/gradle.properties` | `android.builtInKotlin=false` | `connectivity_plus <7.x` aplica plugin Kotlin explícito, incompatible con AGP 9 |
| `android/gradle.properties` | `kotlin.incremental=false` | Pub cache en `C:`, proyecto en `D:` — el compilador incremental de Kotlin falla cross-drive en Windows |
| `pubspec.yaml` | `workmanager: ^0.9.0` | `0.5.x` usa `ShimPluginRegistry` eliminado en Flutter 3.27 |

---

## Workflow de ramas

```
main  ←  feature/<nombre>  (nunca commitear directo a main)
```

```bash
git checkout -b feature/mi-cambio
# ... trabajo ...
git push -u origin feature/mi-cambio
# crear PR en GitHub → merge → eliminar rama
```

---

## Estructura del repositorio

```
CTT/
├── ctt-backend/          Backend FastAPI
│   ├── app/
│   │   ├── models.py     ORM multi-tenant
│   │   ├── schemas.py    Contratos Pydantic (entrada/salida)
│   │   ├── auth.py       Resolución de contexto (mock → firebase)
│   │   ├── state_machine.py  Máquina de estados de ítems
│   │   ├── permissions.py    Matriz de permisos por rol
│   │   ├── routers/      Endpoints (proyectos, items, sync, /me, ...)
│   │   └── seed.py       Datos de demo chilenos
│   ├── tests/            48 tests pytest
│   └── requirements.txt
│
├── ctt-mobile/           App Flutter
│   └── lib/
│       ├── core/         Red, seguridad, sync, config
│       ├── data/         Repositorios (acceso al backend y BD local)
│       ├── domain/       Entidades y enums del dominio
│       └── presentation/ Pantallas y estado (Riverpod)
│
└── frontend/             Cliente web de revisión E2E (HTML + JS)
```
