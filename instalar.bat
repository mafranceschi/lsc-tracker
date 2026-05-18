@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title LSC Tracker - Instalador

:: ══════════════════════════════════════════════════════
::  PERMISOS DE ADMINISTRADOR
:: ══════════════════════════════════════════════════════
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process -FilePath '%~dpnx0' -Verb RunAs"
    exit /b
)

cls
echo.
echo  ==========================================
echo       INSTALADOR LSC TRACKER
echo  ==========================================
echo.

:: ══════════════════════════════════════════════════════
::  VARIABLES
:: ══════════════════════════════════════════════════════
set "INSTALL_DIR=C:\LSC-Tracker"
set "DESKTOP_FOLDER=%PUBLIC%\Desktop\LSC Tracker"
set "ZIP_URL=https://github.com/mafranceschi/lsc-tracker/archive/refs/heads/main.zip"
set "ZIP_FILE=%~dp0lsc-update.zip"
set "ZIP_EXTRACT=%~dp0lsc-update-extract"
set "SRC_DIR=%~dp0"
if "!SRC_DIR:~-1!"=="\" set "SRC_DIR=!SRC_DIR:~0,-1!"

:: ══════════════════════════════════════════════════════
::  [0/5] DESCARGAR ULTIMA VERSION
:: ══════════════════════════════════════════════════════
echo  [0/5] Descargando ultima version desde GitHub...

if exist "!ZIP_EXTRACT!" rmdir /s /q "!ZIP_EXTRACT!" >nul 2>&1
if exist "!ZIP_FILE!"    del /f /q "!ZIP_FILE!"       >nul 2>&1

curl -L --progress-bar --max-time 60 -o "!ZIP_FILE!" "!ZIP_URL!"
if !errorlevel! neq 0 (
    echo        AVISO: Sin internet. Usando version local.
    goto :SKIP_DOWNLOAD
)

echo        Extrayendo archivos...
powershell -NoProfile -Command "Expand-Archive -LiteralPath '!ZIP_FILE!' -DestinationPath '!ZIP_EXTRACT!' -Force"
if !errorlevel! neq 0 (
    echo        AVISO: Error al extraer. Usando version local.
    goto :SKIP_DOWNLOAD
)

set "SRC_DIR=!ZIP_EXTRACT!\lsc-tracker-main"
del /f /q "!ZIP_FILE!" >nul 2>&1
echo        OK: Version actualizada descargada de GitHub
goto :CHECK_SRC

:SKIP_DOWNLOAD

:CHECK_SRC
if not exist "!SRC_DIR!\backend\server.js" (
    echo.
    echo  ERROR: No se encontraron los archivos de la app.
    echo  Verificá tu conexion a internet e intentá de nuevo.
    echo.
    pause
    exit /b 1
)

echo.
echo  Fuente:  !SRC_DIR!
echo  Destino: !INSTALL_DIR!
echo.

:: ══════════════════════════════════════════════════════
::  [1/5] VERIFICAR NODE.JS
:: ══════════════════════════════════════════════════════
echo  [1/5] Verificando Node.js...

node --version >nul 2>&1
if !errorlevel! == 0 (
    for /f "tokens=*" %%v in ('node --version') do echo        OK: Node.js %%v ya instalado
    goto :NODE_OK
)

echo        Node.js no encontrado. Instalando...

winget --version >nul 2>&1
if !errorlevel! == 0 (
    echo        Instalando con winget...
    winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
    if !errorlevel! == 0 goto :REFRESH_PATH
)

echo        Descargando Node.js LTS...
curl -L --progress-bar --max-time 120 -o "%TEMP%\nodejs_lts.msi" "https://nodejs.org/dist/v22.15.0/node-v22.15.0-x64.msi"
if !errorlevel! neq 0 (
    echo.
    echo  ERROR: No se pudo descargar Node.js.
    echo  Instalalo manualmente desde: https://nodejs.org
    pause
    exit /b 1
)
echo        Instalando Node.js...
msiexec /i "%TEMP%\nodejs_lts.msi" /quiet /norestart
del "%TEMP%\nodejs_lts.msi" >nul 2>&1

:REFRESH_PATH
for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYS_PATH=%%b"
set "PATH=!SYS_PATH!;%ProgramFiles%\nodejs"

node --version >nul 2>&1
if !errorlevel! neq 0 (
    echo.
    echo  Node.js fue instalado. Cerrá esta ventana y ejecutá instalar.bat de nuevo.
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('node --version') do echo        OK: Node.js %%v

:NODE_OK
echo.

:: ══════════════════════════════════════════════════════
::  [2/5] COPIAR ARCHIVOS
:: ══════════════════════════════════════════════════════
echo  [2/5] Copiando archivos...

if exist "!INSTALL_DIR!\backend\data" (
    echo        Respaldando base de datos...
    if exist "%TEMP%\lsc_data_bak" rmdir /s /q "%TEMP%\lsc_data_bak"
    xcopy /e /i /q "!INSTALL_DIR!\backend\data" "%TEMP%\lsc_data_bak" >nul
    echo        OK: Backup guardado
)

if exist "!INSTALL_DIR!" rmdir /s /q "!INSTALL_DIR!"
mkdir "!INSTALL_DIR!"
xcopy /e /i /q "!SRC_DIR!\*" "!INSTALL_DIR!\" >nul
if !errorlevel! neq 0 (
    echo.
    echo  ERROR: No se pudieron copiar los archivos.
    pause
    exit /b 1
)

if exist "%TEMP%\lsc_data_bak" (
    echo        Restaurando base de datos...
    if not exist "!INSTALL_DIR!\backend\data" mkdir "!INSTALL_DIR!\backend\data"
    xcopy /e /i /q "%TEMP%\lsc_data_bak\*" "!INSTALL_DIR!\backend\data\" >nul
    rmdir /s /q "%TEMP%\lsc_data_bak" >nul 2>&1
    echo        OK: Datos restaurados
)

echo        OK: Archivos copiados
echo.

:: ══════════════════════════════════════════════════════
::  [3/5] DEPENDENCIAS NPM
:: ══════════════════════════════════════════════════════
echo  [3/5] Instalando dependencias npm...
cd /d "!INSTALL_DIR!\backend"
call npm install --omit=dev
if !errorlevel! neq 0 (
    echo.
    echo  ERROR: Fallo npm install.
    pause
    exit /b 1
)
echo        OK: Dependencias instaladas
echo.

:: ══════════════════════════════════════════════════════
::  [4/5] ACCESOS DIRECTOS
:: ══════════════════════════════════════════════════════
echo  [4/5] Creando accesos directos...
if not exist "!DESKTOP_FOLDER!" mkdir "!DESKTOP_FOLDER!"
copy /y "!INSTALL_DIR!\scripts\ARRANCAR.bat" "!DESKTOP_FOLDER!\ARRANCAR.bat" >nul
copy /y "!INSTALL_DIR!\scripts\DETENER.bat"  "!DESKTOP_FOLDER!\DETENER.bat"  >nul
echo        OK: Carpeta "LSC Tracker" en el Escritorio
echo.

:: ══════════════════════════════════════════════════════
::  [5/5] CONFIG LOCAL
:: ══════════════════════════════════════════════════════
echo  [5/5] Protegiendo configuracion local...
if exist "!INSTALL_DIR!\.env.local" (
    copy /y "!INSTALL_DIR!\.env.local" "!INSTALL_DIR!\.env" >nul
    echo        OK: Config local restaurada
) else (
    echo        OK: Config por defecto aplicada
)

:: Limpiar temporales
if exist "!ZIP_EXTRACT!" rmdir /s /q "!ZIP_EXTRACT!" >nul 2>&1
echo.

echo  ==========================================
echo    INSTALACION COMPLETADA EXITOSAMENTE
echo  ==========================================
echo.
echo  En tu Escritorio encontras la carpeta "LSC Tracker":
echo    ARRANCAR.bat  -- abre la app en el navegador
echo    DETENER.bat   -- apaga el servicio
echo.
echo  Tus datos NO se borran al reinstalar.
echo.
pause
