@echo off
title LSC Tracker

:: Verificar que la app este instalada
if not exist "C:\LSC-Tracker\backend\server.js" (
    echo.
    echo  ERROR: LSC Tracker no esta instalado correctamente.
    echo.
    echo  Pasos para instalar:
    echo   1. Descarga el ZIP desde GitHub
    echo   2. Extraelo en cualquier carpeta
    echo   3. Hace doble click en instalar.bat
    echo   4. Acepta los permisos de administrador
    echo   5. Espera a que termine
    echo   6. Luego usa este archivo ARRANCAR.bat
    echo.
    pause
    exit /b 1
)

:: Matar proceso existente si lo hay (silencioso)
powershell -Command "try { $p=(Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction Stop).OwningProcess; Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch {}" >nul 2>&1
ping 127.0.0.1 -n 3 >nul

:: Iniciar servidor
start /b "" node "C:\LSC-Tracker\backend\server.js"

:: Esperar a que levante
:wait
ping 127.0.0.1 -n 2 >nul
curl -s http://localhost:3000/api/status >nul 2>&1
if %errorlevel% neq 0 goto wait

:: Abrir navegador
start http://localhost:3000
