@echo off
title LSC Tracker
curl -s http://localhost:3000/api/status >nul 2>&1
if %errorlevel% == 0 (
    powershell -Command "try { $p=(Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction Stop).OwningProcess; Stop-Process -Id $p -Force } catch {}"
    ping 127.0.0.1 -n 4 >nul
)
start /b "" node "C:\LSC-Tracker\backend\server.js"
:wait
ping 127.0.0.1 -n 2 >nul
curl -s http://localhost:3000/api/status >nul 2>&1
if %errorlevel% neq 0 goto wait
start http://localhost:3000
