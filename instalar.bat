@echo off
chcp 65001 >nul
title Instalador LSC Tracker

:: Elevar a administrador si hace falta
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process -FilePath '%~dpnx0' -Verb RunAs"
    exit /b
)

:: Lanzar el script de instalacion
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1"
