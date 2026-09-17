@echo off
chcp 65001 >nul
title Buscar pisos nuevos
echo.
echo   Buscando pisos nuevos en Habitaclia y Pisos.com...
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0tools\buscar.ps1"
echo.
echo   Regenerando la pagina...
powershell -ExecutionPolicy Bypass -File "%~dp0tools\construir.ps1"
echo.
echo   Listo. Abriendo la pagina...
start "" "%~dp0index.html"
echo.
pause