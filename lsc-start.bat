@echo off
:: Verificar si ya esta corriendo
curl -s http://localhost:3000/api/status >nul 2>&1
if %errorlevel% == 0 (
    echo Servidor en ejecucion. Reiniciando...
    :: Buscar y matar el proceso que escucha en el puerto 3000
    for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":3000 " ^| findstr "LISTENING"') do (
        taskkill /f /pid %%a >nul 2>&1
    )
    :: Esperar a que se libere el puerto
    timeout /t 2 /nobreak >nul
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
