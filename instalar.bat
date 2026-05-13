@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title LSC Tracker - Instalador

:: ════════════════════════════════════════════════════════════
::  ELEVAR A ADMINISTRADOR
:: ════════════════════════════════════════════════════════════
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~dpnx0\"' -Verb RunAs"
    exit /b
)

cls
echo.
echo  ==========================================
echo       INSTALADOR LSC TRACKER
echo  ==========================================
echo.

:: Carpeta donde esta este .bat (la carpeta del ZIP extraido)
set "SRC_DIR=%~dp0"
:: Quitar barra final si la tiene
if "%SRC_DIR:~-1%"=="\" set "SRC_DIR=%SRC_DIR:~0,-1%"

set "INSTALL_DIR=C:\LSC-Tracker"
set "DESKTOP_FOLDER=%PUBLIC%\Desktop\LSC Tracker"

:: Verificar que estamos en la carpeta correcta
if not exist "%SRC_DIR%\backend\server.js" (
    echo.
    echo  ERROR: No se encontro la carpeta 'backend' junto a este archivo.
    echo.
    echo  Asegurate de extraer el ZIP completo y ejecutar
    echo  instalar.bat desde DENTRO de la carpeta extraida.
    echo.
    pause
    exit /b 1
)

echo  Instalando desde: %SRC_DIR%
echo.

:: ════════════════════════════════════════════════════════════
::  1. NODE.JS
:: ════════════════════════════════════════════════════════════
echo  [1/4] Verificando Node.js...
node --version >nul 2>&1
if %errorlevel% == 0 (
    for /f "tokens=*" %%v in ('node --version') do echo        OK: Node.js %%v ya instalado
    goto :NODE_OK
)

echo        Node.js no encontrado. Instalando...
echo.

:: Intento 1: winget
winget --version >nul 2>&1
if %errorlevel% == 0 (
    echo        Usando winget ^(puede tardar unos minutos^)...
    winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
    if !errorlevel! == 0 goto :REFRESH_PATH
)

:: Intento 2: descarga directa MSI
echo        Descargando Node.js LTS desde nodejs.org...
curl -L --progress-bar "https://nodejs.org/dist/v22.15.0/node-v22.15.0-x64.msi" -o "%TEMP%\nodejs_lts.msi"
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: No se pudo descargar Node.js. Verificar conexion a internet.
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
if %errorlevel% neq 0 (
    echo.
    echo  Node.js fue instalado pero necesita reiniciar la consola.
    echo  Cerrá esta ventana y volvé a ejecutar instalar.bat
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('node --version') do echo        OK: Node.js %%v instalado

:NODE_OK
echo.

:: ════════════════════════════════════════════════════════════
::  2. COPIAR ARCHIVOS A C:\LSC-Tracker
:: ════════════════════════════════════════════════════════════
echo  [2/4] Copiando archivos de la app...

:: Respaldar base de datos si ya existe
if exist "%INSTALL_DIR%\backend\data" (
    echo        Respaldando base de datos...
    if exist "%TEMP%\lsc_data_bak" rmdir /s /q "%TEMP%\lsc_data_bak"
    xcopy /e /i /q "%INSTALL_DIR%\backend\data" "%TEMP%\lsc_data_bak" >nul
    echo        OK: Backup guardado
)

:: Copiar archivos (sobreescribir instalacion anterior)
if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"
mkdir "%INSTALL_DIR%"
xcopy /e /i /q "%SRC_DIR%\*" "%INSTALL_DIR%\" >nul
if %errorlevel% neq 0 (
    echo  ERROR: No se pudo copiar los archivos.
    pause
    exit /b 1
)

:: Restaurar base de datos
if exist "%TEMP%\lsc_data_bak" (
    echo        Restaurando base de datos...
    if not exist "%INSTALL_DIR%\backend\data" mkdir "%INSTALL_DIR%\backend\data"
    xcopy /e /i /q "%TEMP%\lsc_data_bak\*" "%INSTALL_DIR%\backend\data\" >nul
    rmdir /s /q "%TEMP%\lsc_data_bak" >nul 2>&1
    echo        OK: Datos restaurados
)

echo        OK: Archivos copiados a %INSTALL_DIR%
echo.

:: ════════════════════════════════════════════════════════════
::  3. INSTALAR DEPENDENCIAS
:: ════════════════════════════════════════════════════════════
echo  [3/4] Instalando dependencias ^(npm install^)...
cd /d "%INSTALL_DIR%"
call npm install --omit=dev
if %errorlevel% neq 0 (
    echo  ERROR: Fallo npm install.
    pause
    exit /b 1
)
echo        OK: Dependencias instaladas
echo.

:: ════════════════════════════════════════════════════════════
::  4. CONFIGURACION Y ACCESOS DIRECTOS
:: ════════════════════════════════════════════════════════════
echo  [4/4] Configurando y creando accesos directos...

if not exist "%INSTALL_DIR%\.env" (
    (
        echo ENABLE_DB=true
        echo RETENTION_DAYS=30
        echo GOAL_HOURS=12
        echo MAX_LOG_MB=10
    ) > "%INSTALL_DIR%\.env"
)

if not exist "%DESKTOP_FOLDER%" mkdir "%DESKTOP_FOLDER%"
copy /y "%INSTALL_DIR%\scripts\ARRANCAR.bat" "%DESKTOP_FOLDER%\ARRANCAR.bat" >nul
copy /y "%INSTALL_DIR%\scripts\DETENER.bat"  "%DESKTOP_FOLDER%\DETENER.bat"  >nul

echo        OK: Accesos directos en el Escritorio
echo.

:: ════════════════════════════════════════════════════════════
::  LISTO
:: ════════════════════════════════════════════════════════════
echo  ==========================================
echo    INSTALACION COMPLETADA EXITOSAMENTE
echo  ==========================================
echo.
echo  En tu Escritorio encontras:
echo    Carpeta "LSC Tracker"
echo      ARRANCAR.bat  -->  abre la app
echo      DETENER.bat   -->  apaga el servicio
echo.
echo  Tus datos se guardan en:
echo    %INSTALL_DIR%\backend\data\
echo  y NO se borran al reinstalar.
echo.
pause
