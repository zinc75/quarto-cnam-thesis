@echo off
:: Post-render : nettoyage des artefacts LaTeX + renommage du PDF et du .tex.
:: Usage : postrender.bat <lang> <output-dir> [validate]
::   validate  (optional) — check PDF/A-1b compliance via facile.cines.fr before depositing to theses.fr.
::             Requires: curl.exe (pre-installed on Windows 10 v1803+ and Windows 11).
:: Equivalent Windows de postrender.sh — necessite PowerShell (natif Windows 7+).

if "%3"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0postrender.ps1" -Lang %1 -OutputDir %2
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0postrender.ps1" -Lang %1 -OutputDir %2 -Mode %3
)
