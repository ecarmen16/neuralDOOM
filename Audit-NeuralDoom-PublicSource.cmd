@echo off
setlocal DisableDelayedExpansion
set "ND_SCRIPT_ROOT=%~dp0"
title neuralDoom Public Source Audit
where pwsh.exe >nul 2>nul
if errorlevel 1 (
	powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; & ($env:ND_SCRIPT_ROOT + 'tools\neural-rendering\Test-NeuralDoom-PublicSource.ps1') -RepoRoot $env:ND_SCRIPT_ROOT; exit $LASTEXITCODE"
) else (
	pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; & ($env:ND_SCRIPT_ROOT + 'tools\neural-rendering\Test-NeuralDoom-PublicSource.ps1') -RepoRoot $env:ND_SCRIPT_ROOT; exit $LASTEXITCODE"
)
set "ND_AUDIT_EXIT=%ERRORLEVEL%"
echo.
if not "%ND_AUDIT_EXIT%"=="0" echo neuralDoom public-source audit exited with code %ND_AUDIT_EXIT%.
pause
exit /b %ND_AUDIT_EXIT%
