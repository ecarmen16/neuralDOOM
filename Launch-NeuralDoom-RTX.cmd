@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\neural-rendering\Start-NeuralDoom-Dogfood.ps1" -RepoRoot "%~dp0." -RayTracedAO -RayTracedContactShadows -RayTracedGI -DisplayOutput AutoHDR %*
set "ND_EXIT=%ERRORLEVEL%"
if not "%ND_EXIT%"=="0" pause
exit /b %ND_EXIT%
