@echo off
setlocal

set "ND3_EXE=%~dp0RBDoom3BFG.exe"
set "ND3_MOD=%~dp0mod_D3HDP_Lite"
if not exist "%ND3_EXE%" (
	echo RBDoom3BFG.exe was not found beside this launcher.
	pause
	exit /b 1
)
if not exist "%ND3_MOD%" (
	echo mod_D3HDP_Lite was not found beside this launcher.
	pause
	exit /b 1
)

start "Neural Doom 3 - D3HDP" /D "%~dp0" "%ND3_EXE%" ^
	+set fs_game mod_D3HDP_Lite ^
	+set r_graphicsAPI dx12 ^
	+set r_streamlineEnable 1 ^
	+set r_streamlineApplicationId 0 ^
	+set r_neuralBackend 2 ^
	+set r_screenFraction 100 ^
	+set r_renderMode 0 ^
	+set r_useTemporalAA 1 ^
	+set r_antiAliasing 2
