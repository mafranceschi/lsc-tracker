@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title LSC Tracker - Instalador

:: Elevar a administrador si hace falta
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

set "INSTALL_DIR=C:\LSC-Tracker"
set "DESKTOP_FOLDER=%PUBLIC%\Desktop\LSC Tracker"
set "REPO_URL=https://github.com/mafranceschi/lsc-tracker.git"
set "CLONE_DIR=%TEMP%\lsc-tracker-latest"

:: ----------------------------------------
echo  [0/5] Descargando ultima version desde GitHub...
:: ----------------------------------------
git --version >nul 2>&1
if %errorlevel% == 0 (
    echo        Git encontrado. Clonando repositorio...
    if exist "%CLONE_DIR%" rmdir /s /q "%CLONE_DIR%"
    git clone --depth 1 %REPO_URL% "%CLONE_DIR%" >nul 2>&1
    if !errorlevel! == 0 (
        set "SRC_DIR=%CLONE_DIR%"
        echo        OK: Ultima version descargada desde GitHub
    ) else (
        echo        AVISO: Sin internet. Usando archivos locales.
        set "SRC_DIR=%~dp0"
        if "!SRC_DIR:~-1!"=="\" set "SRC_DIR=!SRC_DIR:~0,-1!"
    )
) else (
    echo        AVISO: Git no instalado. Usando archivos locales.
    set "SRC_DIR=%~dp0"
    if "%SRC_DIR:~-1%"=="\" set "SRC_DIR=%SRC_DIR:~0,-1%"
)
echo.

:: Verificar que la fuente es valida
if not exist "%SRC_DIR%\backend\server.js" (
    echo.
    echo  ERROR: No se encontro la carpeta backend.
    echo  Verifica tu conexion a internet o ejecuta desde la carpeta del ZIP.
    echo.
    pause
    exit /b 1
)

echo  Fuente: %SRC_DIR%
echo  Destino: %INSTALL_DIR%
echo.

:: ----------------------------------------
echo  [1/5] Verificando Node.js...
:: ----------------------------------------
node --version >nul 2>&1
if %errorlevel% == 0 (
    for /f "tokens=*" %%v in ('node --version') do echo        OK: Node.js %%v ya instalado
    goto :NODE_OK
)

echo        Node.js no encontrado. Instalando...

winget --version >nul 2>&1
if %errorlevel% == 0 (
    echo        Usando winget para instalar Node.js LTS...
    winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
    if !errorlevel! == 0 goto :REFRESH_PATH
)

echo        Descargando Node.js LTS desde nodejs.org...
curl -L --progress-bar "https://nodejs.org/dist/v22.15.0/node-v22.15.0-x64.msi" -o "%TEMP%\nodejs_lts.msi"
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: No se pudo descargar Node.js. Verifica tu conexion a internet.
    echo  Instalalo manualmente desde: https://nodejs.org
    pause
    exit /b 1
)
echo        Instalando Node.js (puede tardar un momento)...
msiexec /i "%TEMP%\nodejs_lts.msi" /quiet /norestart
del "%TEMP%\nodejs_lts.msi" >nul 2>&1

:REFRESH_PATH
for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYS_PATH=%%b"
set "PATH=!SYS_PATH!;%ProgramFiles%\nodejs"

node --version >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  Node.js fue instalado pero requiere cerrar y abrir la consola.
    echo  Cierra esta ventana y vuelve a ejecutar instalar.bat
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('node --version') do echo        OK: Node.js %%v instalado

:NODE_OK
echo.

:: ----------------------------------------
echo  [2/5] Copiando archivos de la app...
:: ----------------------------------------

if exist "%INSTALL_DIR%\backend\data" (
    echo        Respaldando base de datos existente...
    if exist "%TEMP%\lsc_data_bak" rmdir /s /q "%TEMP%\lsc_data_bak"
    xcopy /e /i /q "%INSTALL_DIR%\backend\data" "%TEMP%\lsc_data_bak" >nul
    echo        OK: Backup guardado
)

if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"
mkdir "%INSTALL_DIR%"
xcopy /e /i /q "%SRC_DIR%\*" "%INSTALL_DIR%\" >nul
if %errorlevel% neq 0 (
    echo  ERROR: No se pudo copiar los archivos a %INSTALL_DIR%
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

echo        OK: Archivos copiados a %INSTALL_DIR%
echo.

:: ----------------------------------------
echo  [3/5] Instalando dependencias npm...
:: ----------------------------------------
cd /d "%INSTALL_DIR%\backend"
call npm install --omit=dev
if %errorlevel% neq 0 (
    echo  ERROR: Fallo npm install.
    pause
    exit /b 1
)
echo        OK: Dependencias instaladas
echo.

:: ----------------------------------------
echo  [4/5] Creando accesos directos...
:: ----------------------------------------
if not exist "%DESKTOP_FOLDER%" mkdir "%DESKTOP_FOLDER%"
copy /y "%INSTALL_DIR%\scripts\ARRANCAR.bat" "%DESKTOP_FOLDER%\ARRANCAR.bat" >nul
copy /y "%INSTALL_DIR%\scripts\DETENER.bat"  "%DESKTOP_FOLDER%\DETENER.bat"  >nul
echo        OK: Carpeta "LSC Tracker" creada en el Escritorio
echo.

:: ----------------------------------------
echo  [5/5] Protegiendo configuracion local...
:: ----------------------------------------
:: Si ya existe un .env.local con configuracion propia, lo restauramos
if exist "%INSTALL_DIR%\.env.local" (
    copy /y "%INSTALL_DIR%\.env.local" "%INSTALL_DIR%\.env" >nul
    echo        OK: Configuracion local restaurada desde .env.local
) else (
    echo        OK: Configuracion por defecto aplicada
)

:: Limpiar clone temporal
if exist "%CLONE_DIR%" rmdir /s /q "%CLONE_DIR%" >nul 2>&1
echo.

echo  ==========================================
echo    INSTALACION COMPLETADA EXITOSAMENTE
echo  ==========================================
echo.
echo  En tu Escritorio encontras la carpeta:
echo    "LSC Tracker"
echo      ARRANCAR.bat  --^>  abre la app en el navegador
echo      DETENER.bat   --^>  apaga el servicio
echo.
echo  Tus datos NO se borran al reinstalar.
echo.
pause
