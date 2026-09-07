@echo off
setlocal
set "ND_ROOT=%~dp0..\..\..\"

set "ND_EXE=%ND_ROOT%neuralDoom.exe"
if not exist "%ND_EXE%" set "ND_EXE=%ND_ROOT%RBDoom3BFG.exe"
set "ND_MOD=%ND_ROOT%mod_D3HDP_Lite"
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

start "neuralDoom - D3HDP" /D "%ND_ROOT%" "%ND_EXE%" ^
	+set fs_game mod_D3HDP_Lite ^
	+set r_graphicsAPI dx12 ^
	+set r_streamlineEnable 1 ^
	+set r_streamlineApplicationId 0 ^
	+set r_neuralBackend 2 ^
	+set r_screenFraction 100 ^
	+set r_renderMode 0 ^
	+set r_useTemporalAA 1 ^
	+set r_antiAliasing 2
