@echo off
:: Verificar si ya esta corriendo
curl -s http://localhost:3000/api/status >nul 2>&1
if %errorlevel% == 0 (
    :: Matar el proceso node en el puerto 3000 via PowerShell
    powershell -Command "try { $pid = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction Stop).OwningProcess; Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue } catch {}"
    :: Esperar a que el puerto se libere
    ping 127.0.0.1 -n 4 >nul
)

:: Iniciar el servidor en background
start /b "" node "%~dp0backend\server.js"

:: Esperar a que arranque
:wait
ping 127.0.0.1 -n 2 >nul
curl -s http://localhost:3000/api/status >nul 2>&1
if %errorlevel% neq 0 goto wait

:: Abrir el navegador
start http://localhost:3000
