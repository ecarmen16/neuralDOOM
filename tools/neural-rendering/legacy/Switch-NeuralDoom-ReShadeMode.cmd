@echo off
setlocal
set "ND_ROOT=%~dp0..\..\..\"

set "ND_MODE=%~1"
if "%ND_MODE%"=="" set "ND_MODE=Embedded"

where pwsh.exe >nul 2>nul
if errorlevel 1 (
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ND_ROOT%tools\neural-rendering\Switch-NeuralDoom-ReShadeMode.ps1" -Mode "%ND_MODE%" -RepoRoot "%ND_ROOT%"
) else (
	pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%ND_ROOT%tools\neural-rendering\Switch-NeuralDoom-ReShadeMode.ps1" -Mode "%ND_MODE%" -RepoRoot "%ND_ROOT%"
)

if errorlevel 1 pause
