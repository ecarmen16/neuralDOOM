@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\neural-rendering\Install-InternalTest.ps1" -RepoRoot "%~dp0." %*
set "ND_EXIT=%ERRORLEVEL%"
pause
exit /b %ND_EXIT%
