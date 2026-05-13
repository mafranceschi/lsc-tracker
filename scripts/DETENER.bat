@echo off
title Detener LSC Tracker
powershell -Command "try { $p=(Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction Stop).OwningProcess; Stop-Process -Id $p -Force; Write-Host 'Servicio detenido.' -ForegroundColor Green } catch { Write-Host 'No habia ningun servicio corriendo.' -ForegroundColor Yellow }"
echo.
pause
