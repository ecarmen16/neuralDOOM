@echo off
setlocal
title neuralDoom Setup
rem Invoke instead of using -File so Windows application-control language modes stay consistent.
where pwsh.exe >nul 2>nul
if errorlevel 1 (
	powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0tools\neural-rendering\Setup-NeuralDoom.ps1' -RepoRoot '%~dp0'"
) else (
	pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0tools\neural-rendering\Setup-NeuralDoom.ps1' -RepoRoot '%~dp0'"
)
set "ND_SETUP_EXIT=%ERRORLEVEL%"
echo.
if not "%ND_SETUP_EXIT%"=="0" echo neuralDoom setup exited with code %ND_SETUP_EXIT%.
pause
exit /b %ND_SETUP_EXIT%
