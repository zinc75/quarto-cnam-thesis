@echo off
:: Post-render : nettoyage des artefacts LaTeX + renommage du PDF et du .tex.
:: Usage : postrender.bat <lang> <output-dir> [pdfa]
::   pdfa  (optional) — run Ghostscript PDF/A-1b conversion after rendering.
::                      Requires Ghostscript: winget install ArtifexSoftware.GhostScript
:: Equivalent Windows de postrender.sh — necessite PowerShell (natif Windows 7+).

if "%3"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0postrender.ps1" -Lang %1 -OutputDir %2
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0postrender.ps1" -Lang %1 -OutputDir %2 -Mode %3
)
