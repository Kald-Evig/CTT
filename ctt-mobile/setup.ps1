# setup.ps1 — Bootstrap del proyecto CTT Mobile.
#
# Ejecutar UNA SOLA VEZ después de instalar Flutter:
#   cd D:\VSCode\CTT\ctt-mobile
#   .\setup.ps1
#
# Requisitos:
#   - Flutter 3.22+ en PATH
#   - Android SDK configurado (ANDROID_HOME)
#   - Java 17+ (para Gradle)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== CTT Mobile — Setup inicial ===" -ForegroundColor Cyan

# Verificar Flutter
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter no encontrado en PATH. Instalar desde: https://docs.flutter.dev/get-started/install/windows"
    exit 1
}

$flutterVersion = (flutter --version 2>&1 | Select-String "Flutter").ToString().Trim()
Write-Host "Flutter encontrado: $flutterVersion" -ForegroundColor Green

# Generar el boilerplate Android que no puede generarse sin flutter create
Write-Host "`n[1/4] Generando boilerplate Android con flutter create..." -ForegroundColor Yellow

# Usamos un directorio temporal para no pisar nuestros archivos
$tmpDir = "$env:TEMP\ctt_mobile_tmp"
if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }

flutter create --org cl.ctt --project-name ctt_mobile --platforms android $tmpDir

# Copiar solo el boilerplate Android (no tocar lib/ ni pubspec.yaml que ya existen)
Write-Host "[2/4] Copiando estructura Android generada..." -ForegroundColor Yellow
$androidSrc = "$tmpDir\android"
$androidDst = "$PSScriptRoot\android"

if (-not (Test-Path $androidDst)) {
    Copy-Item -Recurse -Force $androidSrc $PSScriptRoot
    Write-Host "  -> android/ copiado" -ForegroundColor Green
} else {
    Write-Host "  -> android/ ya existe, omitiendo (OK)" -ForegroundColor DarkYellow
}

# Copiar test de ejemplo si no existe
if (-not (Test-Path "$PSScriptRoot\test\widget_test.dart")) {
    Copy-Item "$tmpDir\test\widget_test.dart" "$PSScriptRoot\test\"
}

# Limpiar temporal
Remove-Item -Recurse -Force $tmpDir

# Instalar dependencias
Write-Host "`n[3/4] Instalando dependencias (flutter pub get)..." -ForegroundColor Yellow
flutter pub get

# Generar código (Drift, Riverpod, Freezed)
Write-Host "`n[4/4] Generando código (build_runner)..." -ForegroundColor Yellow
dart run build_runner build --delete-conflicting-outputs

Write-Host "`n=== Setup completado ===" -ForegroundColor Green
Write-Host "Siguientes pasos:" -ForegroundColor Cyan
Write-Host "  1. Configurar Firebase: flutterfire configure"
Write-Host "  2. Conectar S22 por USB con depuracion habilitada"
Write-Host "  3. flutter run --profile   (NUNCA medir performance en debug)"
