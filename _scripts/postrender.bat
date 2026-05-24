@echo off
:: Post-render : nettoyage des artefacts LaTeX + renommage du PDF et du .tex.
:: Usage : postrender.bat <lang> <output-dir>
:: Equivalent Windows de postrender.sh — necessite PowerShell (natif Windows 7+).

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0postrender.ps1" -Lang %1 -OutputDir %2
