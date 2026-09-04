@echo off
setlocal
title neuralDoom Public Source Audit
where pwsh.exe >nul 2>nul
if errorlevel 1 (
	powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0tools\neural-rendering\Test-NeuralDoom-PublicSource.ps1' -RepoRoot '%~dp0'"
) else (
	pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0tools\neural-rendering\Test-NeuralDoom-PublicSource.ps1' -RepoRoot '%~dp0'"
)
set "ND_AUDIT_EXIT=%ERRORLEVEL%"
echo.
if not "%ND_AUDIT_EXIT%"=="0" echo neuralDoom public-source audit exited with code %ND_AUDIT_EXIT%.
pause
exit /b %ND_AUDIT_EXIT%
