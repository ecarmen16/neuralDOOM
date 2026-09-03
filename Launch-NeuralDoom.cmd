@echo off
setlocal

set "ND_EXE=%~dp0neuralDoom.exe"
if not exist "%ND_EXE%" set "ND_EXE=%~dp0RBDoom3BFG.exe"
if not exist "%ND_EXE%" (
	echo neuralDoom.exe was not found beside this launcher.
	pause
	exit /b 1
)

start "neuralDoom" /D "%~dp0" "%ND_EXE%" ^
	+set r_graphicsAPI dx12 ^
	+set r_streamlineEnable 1 ^
	+set r_streamlineApplicationId 0 ^
	+set r_neuralBackend 2 ^
	+set r_screenFraction 100 ^
	+set r_renderMode 0 ^
	+set r_useTemporalAA 1 ^
	+set r_antiAliasing 2
