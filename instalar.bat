@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title LSC Tracker - Instalador

:: ── PERMISOS ADMIN ─────────────────────────────────────
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process -FilePath '%~dpnx0' -Verb RunAs"
    exit /b
)

cls
echo.
echo  INSTALADOR LSC TRACKER
echo  ----------------------------------------
echo.

set "INSTALL_DIR=C:\LSC-Tracker"
set "DESKTOP_FOLDER=%PUBLIC%\Desktop\LSC Tracker"
set "ZIP_URL=https://github.com/mafranceschi/lsc-tracker/archive/refs/heads/main.zip"
set "BAT_DIR=%~dp0"
if "%BAT_DIR:~-1%"=="\" set "BAT_DIR=%BAT_DIR:~0,-1%"
set "ZIP_FILE=%BAT_DIR%\lsc-update.zip"
set "ZIP_EXTRACT=%BAT_DIR%\lsc-update-extract"
set "SRC_DIR=%BAT_DIR%"

:: ── [0/5] DESCARGAR ULTIMA VERSION ─────────────────────
echo  [0/5] Descargando ultima version desde GitHub...

if exist "%ZIP_EXTRACT%" rmdir /s /q "%ZIP_EXTRACT%" >nul 2>&1
if exist "%ZIP_FILE%"    del /f /q "%ZIP_FILE%"      >nul 2>&1

echo        Conectando a GitHub...
curl -L -s -S --max-time 60 -o "%ZIP_FILE%" "%ZIP_URL%"
if %errorlevel% neq 0 (
    echo        AVISO: Sin internet. Se usara la version local.
    goto :CHECK_SRC
)

echo        Extrayendo archivos...
powershell -NoProfile -Command "Expand-Archive -LiteralPath '%ZIP_FILE%' -DestinationPath '%ZIP_EXTRACT%' -Force" >nul 2>&1
if %errorlevel% neq 0 (
    echo        AVISO: Error al extraer el ZIP. Se usara la version local.
    goto :CHECK_SRC
)

set "SRC_DIR=%ZIP_EXTRACT%\lsc-tracker-main"
del /f /q "%ZIP_FILE%" >nul 2>&1
echo        OK: Ultima version descargada

:CHECK_SRC
if not exist "%SRC_DIR%\backend\server.js" (
    echo.
    echo  ERROR: No se encontraron los archivos de la app.
    echo  Verificá tu conexion a internet e intentá de nuevo.
    echo.
    pause
    exit /b 1
)
echo.

:: ── [1/5] NODE.JS ───────────────────────────────────────
echo  [1/5] Verificando Node.js...

node --version >nul 2>&1
if %errorlevel% == 0 (
    for /f "tokens=*" %%v in ('node --version') do echo        OK: Node.js %%v
    goto :NODE_OK
)

echo        Node.js no encontrado. Instalando...
winget --version >nul 2>&1
if %errorlevel% == 0 (
    echo        Instalando con winget...
    winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
    if %errorlevel% == 0 goto :REFRESH_PATH
)

echo        Descargando instalador de Node.js...
curl -L -s -S --max-time 120 -o "%TEMP%\nodejs_lts.msi" "https://nodejs.org/dist/v22.15.0/node-v22.15.0-x64.msi"
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: No se pudo descargar Node.js.
    echo  Instalalo desde: https://nodejs.org
    pause
    exit /b 1
)
echo        Instalando Node.js...
msiexec /i "%TEMP%\nodejs_lts.msi" /quiet /norestart
del /f /q "%TEMP%\nodejs_lts.msi" >nul 2>&1

:REFRESH_PATH
for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "PATH=%%b;%ProgramFiles%\nodejs"

node --version >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  Node.js instalado. Cerrá esta ventana y ejecutá instalar.bat de nuevo.
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('node --version') do echo        OK: Node.js %%v

:NODE_OK
echo.

:: ── [2/5] COPIAR ARCHIVOS ───────────────────────────────
echo  [2/5] Copiando archivos...

if exist "%INSTALL_DIR%\backend\data" (
    echo        Respaldando base de datos...
    if exist "%TEMP%\lsc_data_bak" rmdir /s /q "%TEMP%\lsc_data_bak"
    xcopy /e /i /q "%INSTALL_DIR%\backend\data" "%TEMP%\lsc_data_bak" >nul
    echo        OK: Backup guardado
)

if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"
mkdir "%INSTALL_DIR%"
xcopy /e /i /q "%SRC_DIR%\*" "%INSTALL_DIR%\" >nul
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: No se pudieron copiar los archivos.
    pause
    exit /b 1
)

if exist "%TEMP%\lsc_data_bak" (
    echo        Restaurando base de datos...
    if not exist "%INSTALL_DIR%\backend\data" mkdir "%INSTALL_DIR%\backend\data"
    xcopy /e /i /q "%TEMP%\lsc_data_bak\*" "%INSTALL_DIR%\backend\data\" >nul
    rmdir /s /q "%TEMP%\lsc_data_bak" >nul 2>&1
    echo        OK: Datos restaurados
)
echo        OK: Archivos copiados
echo.

:: ── [3/5] NPM INSTALL ───────────────────────────────────
echo  [3/5] Instalando dependencias npm...
cd /d "%INSTALL_DIR%\backend"

:: Buscar npm explicitamente si no esta en PATH
where npm >nul 2>&1
if %errorlevel% neq 0 (
    set "PATH=%PATH%;%ProgramFiles%\nodejs"
)

call npm install --omit=dev
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: Fallo npm install.
    pause
    exit /b 1
)
echo        OK: Dependencias instaladas
echo.

:: ── [4/5] ACCESOS DIRECTOS ─────────────────────────────
echo  [4/5] Creando accesos directos en el Escritorio...
if not exist "%DESKTOP_FOLDER%" mkdir "%DESKTOP_FOLDER%"
copy /y "%INSTALL_DIR%\scripts\ARRANCAR.bat" "%DESKTOP_FOLDER%\ARRANCAR.bat" >nul
copy /y "%INSTALL_DIR%\scripts\DETENER.bat"  "%DESKTOP_FOLDER%\DETENER.bat"  >nul
echo        OK: Carpeta "LSC Tracker" creada en el Escritorio
echo.

:: ── [5/5] CONFIG ────────────────────────────────────────
echo  [5/5] Protegiendo configuracion local...
if exist "%INSTALL_DIR%\.env.local" (
    copy /y "%INSTALL_DIR%\.env.local" "%INSTALL_DIR%\.env" >nul
    echo        OK: Config local restaurada
) else (
    echo        OK: Config por defecto aplicada
)

:: Limpiar temporales
if exist "%ZIP_EXTRACT%" rmdir /s /q "%ZIP_EXTRACT%" >nul 2>&1
echo.

echo  ----------------------------------------
echo    INSTALACION COMPLETADA EXITOSAMENTE
echo  ----------------------------------------
echo.
echo  En tu Escritorio esta la carpeta "LSC Tracker":
echo    ARRANCAR.bat  -- abre la app en el navegador
echo    DETENER.bat   -- apaga el servicio
echo.
echo  Tus datos NO se borran al reinstalar.
echo.
pause
