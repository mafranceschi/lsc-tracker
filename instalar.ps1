#Requires -Version 5.0
# ═══════════════════════════════════════════════════════════════════
#  INSTALADOR LSC TRACKER
#  Instala Node.js si hace falta, descarga la app y crea los
#  accesos directos ARRANCAR / DETENER en el Escritorio.
# ═══════════════════════════════════════════════════════════════════

# ── Auto-elevacion a Administrador ─────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal]
          [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Solicitando permisos de administrador..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ErrorActionPreference = 'Stop'

$INSTALL_DIR    = "C:\LSC-Tracker"
$DESKTOP_FOLDER = "$env:PUBLIC\Desktop\LSC Tracker"   # visible para todos los usuarios
$GITHUB_ZIP     = "https://github.com/mafranceschi/lsc-tracker/archive/refs/heads/main.zip"

function Write-Step($n, $msg) { Write-Host ""; Write-Host "  [$n] $msg" -ForegroundColor Cyan }
function Write-OK($msg)        { Write-Host "      OK  $msg" -ForegroundColor Green }
function Write-Info($msg)      { Write-Host "       >  $msg" -ForegroundColor Gray }

Clear-Host
Write-Host ""
Write-Host "  ==========================================" -ForegroundColor Blue
Write-Host "         INSTALADOR LSC TRACKER             " -ForegroundColor Blue
Write-Host "  ==========================================" -ForegroundColor Blue
Write-Host ""

# ── 1. Node.js ──────────────────────────────────────────────────────
Write-Step "1/5" "Verificando Node.js"

$nodePath  = ""
$nodeFound = $false
foreach ($candidate in @(
    "node",
    "$env:ProgramFiles\nodejs\node.exe",
    "$env:ProgramFiles(x86)\nodejs\node.exe"
)) {
    try {
        $ver = & $candidate --version 2>$null
        if ($ver -match 'v\d') { $nodeFound = $true; $nodePath = $candidate; break }
    } catch {}
}

if ($nodeFound) {
    Write-OK "Node.js $ver ya instalado"
} else {
    Write-Info "Node.js no encontrado. Instalando..."

    $installed = $false

    # Intento 1: winget
    try {
        & winget install --id OpenJS.NodeJS.LTS `
            --accept-source-agreements --accept-package-agreements --silent 2>$null
        if ($LASTEXITCODE -eq 0) { $installed = $true; Write-OK "Node.js instalado con winget" }
    } catch {}

    # Intento 2: descarga directa del MSI
    if (-not $installed) {
        Write-Info "Descargando instalador de Node.js desde nodejs.org..."
        try {
            $index   = Invoke-RestMethod "https://nodejs.org/dist/index.json" -UseBasicParsing
            $ltsVer  = ($index | Where-Object { $_.lts } | Select-Object -First 1).version
            $msiUrl  = "https://nodejs.org/dist/$ltsVer/node-$ltsVer-x64.msi"
            $msiPath = "$env:TEMP\nodejs-lts.msi"
            Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
            Start-Process msiexec -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
            Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
            $installed = $true
            Write-OK "Node.js instalado correctamente"
        } catch {
            Write-Host "  ERROR: No se pudo instalar Node.js automaticamente." -ForegroundColor Red
            Write-Host "  Instalalalo manualmente desde https://nodejs.org y volvé a ejecutar este script." -ForegroundColor Yellow
            Read-Host "  Presiona ENTER para salir"
            exit 1
        }
    }

    # Refrescar PATH para esta sesion
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

# ── 2. Descargar / actualizar app ───────────────────────────────────
Write-Step "2/5" "Descargando LSC Tracker desde GitHub"

# Respaldar base de datos si ya existia
$DATA_DIR    = "$INSTALL_DIR\backend\data"
$DATA_BACKUP = "$env:TEMP\lsc-data-backup"

if (Test-Path $DATA_DIR) {
    Write-Info "Respaldando base de datos existente..."
    if (Test-Path $DATA_BACKUP) { Remove-Item $DATA_BACKUP -Recurse -Force }
    Copy-Item $DATA_DIR $DATA_BACKUP -Recurse
    Write-OK "Backup guardado en $DATA_BACKUP"
}

# Borrar instalacion anterior
if (Test-Path $INSTALL_DIR) { Remove-Item $INSTALL_DIR -Recurse -Force }
New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null

# Descargar y extraer
$ZIP_PATH     = "$env:TEMP\lsc-tracker.zip"
$EXTRACT_PATH = "$env:TEMP\lsc-extract"
Write-Info "Descargando..."
Invoke-WebRequest -Uri $GITHUB_ZIP -OutFile $ZIP_PATH -UseBasicParsing
if (Test-Path $EXTRACT_PATH) { Remove-Item $EXTRACT_PATH -Recurse -Force }
Expand-Archive -Path $ZIP_PATH -DestinationPath $EXTRACT_PATH -Force
Copy-Item "$EXTRACT_PATH\lsc-tracker-main\*" $INSTALL_DIR -Recurse -Force
Remove-Item $ZIP_PATH     -Force -ErrorAction SilentlyContinue
Remove-Item $EXTRACT_PATH -Recurse -Force -ErrorAction SilentlyContinue
Write-OK "App descargada en $INSTALL_DIR"

# Restaurar base de datos
if (Test-Path $DATA_BACKUP) {
    Write-Info "Restaurando base de datos..."
    if (-not (Test-Path $DATA_DIR)) { New-Item -ItemType Directory -Path $DATA_DIR -Force | Out-Null }
    Copy-Item "$DATA_BACKUP\*" $DATA_DIR -Recurse -Force
    Remove-Item $DATA_BACKUP -Recurse -Force
    Write-OK "Base de datos restaurada - tus datos siguen ahi"
}

# ── 3. Dependencias npm ─────────────────────────────────────────────
Write-Step "3/5" "Instalando dependencias"
Set-Location $INSTALL_DIR
Write-Info "Ejecutando npm install (puede tardar un momento)..."
& npm install --omit=dev 2>&1 | Out-Null
Write-OK "Dependencias instaladas"

# ── 4. Configuracion (.env) ─────────────────────────────────────────
Write-Step "4/5" "Configurando la app"
$ENV_FILE = "$INSTALL_DIR\.env"
if (-not (Test-Path $ENV_FILE)) {
    @"
ENABLE_DB=true
RETENTION_DAYS=30
GOAL_HOURS=12
MAX_LOG_MB=10
"@ | Set-Content $ENV_FILE -Encoding UTF8
    Write-OK "Archivo de configuracion creado"
} else {
    Write-OK "Configuracion existente conservada"
}

# ── 5. Accesos directos en el Escritorio ────────────────────────────
Write-Step "5/5" "Creando accesos directos"
if (-not (Test-Path $DESKTOP_FOLDER)) {
    New-Item -ItemType Directory -Path $DESKTOP_FOLDER -Force | Out-Null
}

# ARRANCAR.bat
@"
@echo off
title LSC Tracker - Iniciando...
curl -s http://localhost:3000/api/status >nul 2>&1
if %errorlevel% == 0 (
    powershell -Command "try { `$p = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction Stop).OwningProcess; Stop-Process -Id `$p -Force } catch {}"
    ping 127.0.0.1 -n 4 >nul
)
start /b "" node "$INSTALL_DIR\backend\server.js"
:wait
ping 127.0.0.1 -n 2 >nul
curl -s http://localhost:3000/api/status >nul 2>&1
if %errorlevel% neq 0 goto wait
start http://localhost:3000
"@ | Set-Content "$DESKTOP_FOLDER\ARRANCAR.bat" -Encoding ASCII

# DETENER.bat
@"
@echo off
title LSC Tracker - Deteniendo...
powershell -Command "try { `$p = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction Stop).OwningProcess; Stop-Process -Id `$p -Force; Write-Host 'Servicio detenido correctamente.' -ForegroundColor Green } catch { Write-Host 'No habia ningun servicio corriendo.' -ForegroundColor Yellow }"
echo.
pause
"@ | Set-Content "$DESKTOP_FOLDER\DETENER.bat" -Encoding ASCII

Write-OK "Carpeta 'LSC Tracker' creada en el Escritorio"

# ── Resumen final ───────────────────────────────────────────────────
Write-Host ""
Write-Host "  ==========================================" -ForegroundColor Green
Write-Host "    INSTALACION COMPLETADA CORRECTAMENTE    " -ForegroundColor Green
Write-Host "  ==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  En el Escritorio vas a ver la carpeta:" -ForegroundColor White
Write-Host "    LSC Tracker\" -ForegroundColor Yellow
Write-Host "      ARRANCAR.bat  -->  abre la app en el navegador" -ForegroundColor White
Write-Host "      DETENER.bat   -->  detiene el servicio" -ForegroundColor White
Write-Host ""
Write-Host "  Tus datos (base de datos) se guardan en:" -ForegroundColor White
Write-Host "    $INSTALL_DIR\backend\data\" -ForegroundColor Yellow
Write-Host "  y NO se borran al actualizar la app." -ForegroundColor White
Write-Host ""
Read-Host "  Presiona ENTER para cerrar"
