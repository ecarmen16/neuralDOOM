@echo off
setlocal

set "ND_MODE=%~1"
if "%ND_MODE%"=="" set "ND_MODE=Embedded"

where pwsh.exe >nul 2>nul
if errorlevel 1 (
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\neural-rendering\Switch-NeuralDoom-ReShadeMode.ps1" -Mode "%ND_MODE%" -RepoRoot "%~dp0"
) else (
	pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\neural-rendering\Switch-NeuralDoom-ReShadeMode.ps1" -Mode "%ND_MODE%" -RepoRoot "%~dp0"
)

if errorlevel 1 pause
