@echo off
:: Verificar si ya esta corriendo
curl -s http://localhost:3000/api/status >nul 2>&1
if %errorlevel% == 0 (
    start http://localhost:3000
    exit /b
)

:: Iniciar el servidor en background
start /b "" node "%~dp0backend\server.js"

:: Esperar a que arranque
:wait
timeout /t 1 /nobreak >nul
curl -s http://localhost:3000/api/status >nul 2>&1
if %errorlevel% neq 0 goto wait

:: Abrir el navegador
start http://localhost:3000
