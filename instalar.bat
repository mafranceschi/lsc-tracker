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

set "INSTALL_DIR=C:\LSC-Tracker"
set "DESKTOP_FOLDER=%PUBLIC%\Desktop\LSC Tracker"
set "ZIP_TMP=%TEMP%\lsc_download.zip"
set "EXT_TMP=%TEMP%\lsc_extract"

:: ════════════════════════════════════════════════════════════
::  1. NODE.JS
:: ════════════════════════════════════════════════════════════
echo  [1/5] Verificando Node.js...
node --version >nul 2>&1
if %errorlevel% == 0 (
    for /f "tokens=*" %%v in ('node --version') do echo        OK: Node.js %%v ya instalado
    goto :NODE_OK
)

echo        Node.js no encontrado. Instalando...
echo.

:: Intento 1: winget (disponible en Windows 10/11)
winget --version >nul 2>&1
if %errorlevel% == 0 (
    echo        Usando winget para instalar Node.js...
    winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
    goto :REFRESH_PATH
)

:: Intento 2: descarga directa del instalador MSI
echo        Descargando instalador de Node.js LTS...
curl -L --progress-bar "https://nodejs.org/dist/v22.15.0/node-v22.15.0-x64.msi" -o "%TEMP%\nodejs_lts.msi"
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: No se pudo descargar Node.js.
    echo  Verificar conexion a internet e intentar de nuevo.
    echo  O instalarlo manualmente desde: https://nodejs.org
    echo.
    pause
    exit /b 1
)
echo        Instalando Node.js ^(puede tardar un momento^)...
msiexec /i "%TEMP%\nodejs_lts.msi" /quiet /norestart
del "%TEMP%\nodejs_lts.msi" >nul 2>&1

:REFRESH_PATH
:: Actualizar PATH en esta sesion
for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYS_PATH=%%b"
for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USR_PATH=%%b"
set "PATH=!SYS_PATH!;!USR_PATH!;%ProgramFiles%\nodejs"

node --version >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  AVISO: Node.js fue instalado pero requiere reiniciar la consola.
    echo  Cerrá esta ventana, abrí una nueva como Administrador y volvé a ejecutar instalar.bat
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('node --version') do echo        OK: Node.js %%v instalado correctamente

:NODE_OK
echo.

:: ════════════════════════════════════════════════════════════
::  2. DESCARGAR APP DESDE GITHUB
:: ════════════════════════════════════════════════════════════
echo  [2/5] Descargando LSC Tracker desde GitHub...

:: Respaldar base de datos si ya existe
if exist "%INSTALL_DIR%\backend\data" (
    echo        Respaldando base de datos existente...
    if exist "%TEMP%\lsc_data_bak" rmdir /s /q "%TEMP%\lsc_data_bak"
    xcopy /e /i /q "%INSTALL_DIR%\backend\data" "%TEMP%\lsc_data_bak" >nul
    echo        OK: Backup guardado
)

:: Borrar instalacion anterior
if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"
mkdir "%INSTALL_DIR%"

:: Descargar ZIP
curl -L --progress-bar "https://github.com/mafranceschi/lsc-tracker/archive/refs/heads/main.zip" -o "%ZIP_TMP%"
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: No se pudo descargar la app desde GitHub.
    echo  Verificar conexion a internet.
    echo.
    pause
    exit /b 1
)

:: Extraer ZIP (tar viene incluido en Windows 10+)
echo        Extrayendo archivos...
if exist "%EXT_TMP%" rmdir /s /q "%EXT_TMP%"
mkdir "%EXT_TMP%"
tar -xf "%ZIP_TMP%" -C "%EXT_TMP%" >nul 2>&1
if %errorlevel% neq 0 (
    :: Fallback con PowerShell si tar falla
    powershell -Command "Expand-Archive -Path '%ZIP_TMP%' -DestinationPath '%EXT_TMP%' -Force"
)
xcopy /e /i /q "%EXT_TMP%\lsc-tracker-main\*" "%INSTALL_DIR%\" >nul
rmdir /s /q "%EXT_TMP%" >nul 2>&1
del "%ZIP_TMP%" >nul 2>&1

:: Restaurar base de datos
if exist "%TEMP%\lsc_data_bak" (
    echo        Restaurando base de datos...
    if not exist "%INSTALL_DIR%\backend\data" mkdir "%INSTALL_DIR%\backend\data"
    xcopy /e /i /q "%TEMP%\lsc_data_bak\*" "%INSTALL_DIR%\backend\data\" >nul
    rmdir /s /q "%TEMP%\lsc_data_bak" >nul 2>&1
    echo        OK: Datos restaurados correctamente
)

echo        OK: App descargada en %INSTALL_DIR%
echo.

:: ════════════════════════════════════════════════════════════
::  3. INSTALAR DEPENDENCIAS NPM
:: ════════════════════════════════════════════════════════════
echo  [3/5] Instalando dependencias ^(npm install^)...
cd /d "%INSTALL_DIR%"
call npm install --omit=dev
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: Fallo npm install. Revisa la conexion a internet.
    pause
    exit /b 1
)
echo        OK: Dependencias instaladas
echo.

:: ════════════════════════════════════════════════════════════
::  4. CONFIGURACION (.env)
:: ════════════════════════════════════════════════════════════
echo  [4/5] Configurando la app...
if not exist "%INSTALL_DIR%\.env" (
    (
        echo ENABLE_DB=true
        echo RETENTION_DAYS=30
        echo GOAL_HOURS=12
        echo MAX_LOG_MB=10
    ) > "%INSTALL_DIR%\.env"
    echo        OK: Archivo de configuracion creado
) else (
    echo        OK: Configuracion existente conservada
)
echo.

:: ════════════════════════════════════════════════════════════
::  5. CREAR ACCESOS DIRECTOS EN EL ESCRITORIO
:: ════════════════════════════════════════════════════════════
echo  [5/5] Creando accesos directos en el Escritorio...
if not exist "%DESKTOP_FOLDER%" mkdir "%DESKTOP_FOLDER%"

copy /y "%INSTALL_DIR%\scripts\ARRANCAR.bat" "%DESKTOP_FOLDER%\ARRANCAR.bat" >nul
copy /y "%INSTALL_DIR%\scripts\DETENER.bat"  "%DESKTOP_FOLDER%\DETENER.bat"  >nul

echo        OK: Carpeta 'LSC Tracker' creada en el Escritorio
echo.

:: ════════════════════════════════════════════════════════════
::  RESUMEN FINAL
:: ════════════════════════════════════════════════════════════
echo  ==========================================
echo    INSTALACION COMPLETADA EXITOSAMENTE
echo  ==========================================
echo.
echo  En tu Escritorio encontras la carpeta:
echo.
echo    LSC Tracker\
echo      ARRANCAR.bat   --^>  abre la app en el navegador
echo      DETENER.bat    --^>  apaga el servicio
echo.
echo  Tus datos se guardan en:
echo    %INSTALL_DIR%\backend\data\
echo  y NO se borran al reinstalar o actualizar.
echo.
echo  Para actualizar la app en el futuro, simplemente
echo  volvé a ejecutar este mismo instalar.bat
echo.
pause
