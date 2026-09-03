@echo off
setlocal

set "ND_EXE=%~dp0neuralDoom.exe"
if not exist "%ND_EXE%" set "ND_EXE=%~dp0RBDoom3BFG.exe"
set "ND_MOD=%~dp0mod_D3HDP_Lite"
if not exist "%ND_EXE%" (
	echo neuralDoom.exe was not found beside this launcher.
	pause
	exit /b 1
)
if not exist "%ND_MOD%" (
	echo mod_D3HDP_Lite was not found beside this launcher.
	pause
	exit /b 1
)
if exist "%~dp0dxgi.dll" (
	echo dxgi.dll is still in proxy mode. Run Switch-NeuralDoom-ReShadeMode.cmd first.
	pause
	exit /b 1
)
if not exist "%~dp0neuraldoom-reshade64.dll" (
	echo neuraldoom-reshade64.dll was not found. Run Switch-NeuralDoom-ReShadeMode.cmd first.
	pause
	exit /b 1
)

start "neuralDoom - Embedded NR + D3HDP" /D "%~dp0" "%ND_EXE%" ^
	+set fs_game mod_D3HDP_Lite ^
	+set r_graphicsAPI dx12 ^
	+set r_neuralCompatibilityEnable 1 ^
	+set r_streamlineEnable 1 ^
	+set r_streamlineApplicationId 0 ^
	+set r_neuralBackend 2 ^
	+set r_screenFraction 100 ^
	+set r_renderMode 0 ^
	+set r_useTemporalAA 1 ^
	+set r_antiAliasing 2
