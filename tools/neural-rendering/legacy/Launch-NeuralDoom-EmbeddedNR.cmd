@echo off
setlocal
set "ND_ROOT=%~dp0..\..\..\"

set "ND_EXE=%ND_ROOT%neuralDoom.exe"
if not exist "%ND_EXE%" set "ND_EXE=%ND_ROOT%RBDoom3BFG.exe"
if not exist "%ND_EXE%" (
	echo neuralDoom.exe was not found beside this launcher.
	pause
	exit /b 1
)
if exist "%ND_ROOT%dxgi.dll" (
	echo dxgi.dll is still in proxy mode. Run Switch-NeuralDoom-ReShadeMode.cmd first.
	pause
	exit /b 1
)
if not exist "%ND_ROOT%neuraldoom-reshade64.dll" (
	echo neuraldoom-reshade64.dll was not found. Run Switch-NeuralDoom-ReShadeMode.cmd first.
	pause
	exit /b 1
)

start "neuralDoom - Embedded NR" /D "%ND_ROOT%" "%ND_EXE%" ^
	+set r_graphicsAPI dx12 ^
	+set r_neuralCompatibilityEnable 1 ^
	+set r_streamlineEnable 1 ^
	+set r_streamlineApplicationId 0 ^
	+set r_neuralBackend 2 ^
	+set r_screenFraction 100 ^
	+set r_renderMode 0 ^
	+set r_useTemporalAA 1 ^
	+set r_antiAliasing 2
