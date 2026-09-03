/*
===========================================================================

Doom 3 BFG Edition GPL Source Code
Copyright (C) 1993-2012 id Software LLC, a ZeniMax Media company.

This file is part of the Doom 3 BFG Edition Source Code ("Doom 3 BFG Edition Source Code").

===========================================================================
*/

#include "precompiled.h"
#pragma hdrstop

#include "RenderCommon.h"
#include "NeuralCompatibility.h"

#if defined( _WIN32 )
	#include <Windows.h>
	#include <Psapi.h>
#endif

idCVar r_neuralCompatibilityEnable( "r_neuralCompatibilityEnable", "0", CVAR_RENDERER | CVAR_BOOL | CVAR_INIT | CVAR_NEW, "explicitly load a local ReShade compatibility runtime before D3D12 device creation" );
idCVar r_neuralCompatibilityRuntime( "r_neuralCompatibilityRuntime", "neuraldoom-reshade64.dll", CVAR_RENDERER | CVAR_INIT | CVAR_NEW, "local ReShade runtime filename used by the optional compatibility startup path" );
idCVar r_neuralCompatibilityProfile( "r_neuralCompatibilityProfile", "", CVAR_RENDERER | CVAR_INIT | CVAR_NEW, "optional RenoDX DLSS5 startup profile: empty preserves reshade.ini, working uses the validated NeuralDoom values, neutral resets strengths to 1" );

namespace
{
	typedef void ( *reshadeSetConfigValue_t )( void* module, void* runtime, const char* section, const char* key, const char* value );

	struct neuralCompatibilityState_t
	{
		bool requested = false;
		bool initialized = false;
		bool existingRuntime = false;
		bool profileApplied = false;
		void* module = NULL;
		const char* result = "not attempted";
	};

	neuralCompatibilityState_t compatibilityState;

#if defined( _WIN32 )
	HMODULE FindLoadedReShade()
	{
		HMODULE modules[1024];
		DWORD bytesNeeded = 0;
		if( !K32EnumProcessModules( GetCurrentProcess(), modules, sizeof( modules ), &bytesNeeded ) )
		{
			return NULL;
		}

		const DWORD moduleCount = Min( bytesNeeded / ( DWORD )sizeof( HMODULE ), ( DWORD )_countof( modules ) );
		for( DWORD i = 0; i < moduleCount; i++ )
		{
			if( GetProcAddress( modules[i], "ReShadeVersion" ) != NULL )
			{
				return modules[i];
			}
		}
		return NULL;
	}

	bool BuildRuntimePath( wchar_t* destination, size_t destinationCount )
	{
		if( destination == NULL || destinationCount == 0 )
		{
			return false;
		}

		wchar_t executablePath[MAX_OSPATH];
		const DWORD executableLength = GetModuleFileNameW( NULL, executablePath, _countof( executablePath ) );
		if( executableLength == 0 || executableLength >= _countof( executablePath ) )
		{
			return false;
		}

		wchar_t* separator = wcsrchr( executablePath, L'\\' );
		if( separator == NULL )
		{
			return false;
		}
		separator[1] = L'\0';

		wchar_t runtimeName[MAX_OSPATH];
		const int converted = MultiByteToWideChar( CP_UTF8, 0, r_neuralCompatibilityRuntime.GetString(), -1, runtimeName, _countof( runtimeName ) );
		if( converted == 0 )
		{
			return false;
		}

		return swprintf_s( destination, destinationCount, L"%ls%ls", executablePath, runtimeName ) > 0;
	}

	void SetProfileValue( reshadeSetConfigValue_t setConfigValue, const char* key, const char* value )
	{
		setConfigValue( NULL, NULL, "RenoDX.DLSS5", key, value );
	}

	bool ApplyCompatibilityProfile( HMODULE module )
	{
		const char* profile = r_neuralCompatibilityProfile.GetString();
		if( profile == NULL || profile[0] == '\0' )
		{
			return false;
		}
		if( idStr::Icmp( profile, "working" ) && idStr::Icmp( profile, "neutral" ) )
		{
			common->Warning( "Unknown r_neuralCompatibilityProfile '%s'; preserving existing RenoDX settings", profile );
			return false;
		}

		const reshadeSetConfigValue_t setConfigValue = reinterpret_cast<reshadeSetConfigValue_t>( GetProcAddress( module, "ReShadeSetConfigValue" ) );
		if( setConfigValue == NULL )
		{
			common->Warning( "Neural compatibility runtime does not export ReShadeSetConfigValue; profile '%s' was not applied", profile );
			return false;
		}

		SetProfileValue( setConfigValue, "NeuralUplift", "1" );
		SetProfileValue( setConfigValue, "NRAutoMask", "0" );
		SetProfileValue( setConfigValue, "NREnableUpscaling", "0" );
		SetProfileValue( setConfigValue, "NRDepthMode", "0" );
		SetProfileValue( setConfigValue, "NRPreset", "3" );
		SetProfileValue( setConfigValue, "NRStyle", "1" );
		SetProfileValue( setConfigValue, "NRUICorrection", "0" );

		if( !idStr::Icmp( profile, "working" ) )
		{
			SetProfileValue( setConfigValue, "NRIntensity", "1.45" );
			SetProfileValue( setConfigValue, "NRLocalTone", "1.01" );
			SetProfileValue( setConfigValue, "NRLocalStructure", "1.03" );
			SetProfileValue( setConfigValue, "NRSkinStructure", "0.75" );
			SetProfileValue( setConfigValue, "NRColorStrength", "0.89" );
			SetProfileValue( setConfigValue, "NRTransferStrength", "0.88" );
			SetProfileValue( setConfigValue, "NRPaperWhiteScale", "0.05" );
		}
		else if( !idStr::Icmp( profile, "neutral" ) )
		{
			SetProfileValue( setConfigValue, "NRIntensity", "1.0" );
			SetProfileValue( setConfigValue, "NRLocalTone", "1.0" );
			SetProfileValue( setConfigValue, "NRLocalStructure", "1.0" );
			SetProfileValue( setConfigValue, "NRSkinStructure", "1.0" );
			SetProfileValue( setConfigValue, "NRColorStrength", "1.0" );
			SetProfileValue( setConfigValue, "NRTransferStrength", "1.0" );
			SetProfileValue( setConfigValue, "NRPaperWhiteScale", "1.0" );
		}
		common->Printf( "Neural compatibility profile '%s' applied before add-on initialization\n", profile );
		return true;
	}
#endif
}

bool R_NeuralCompatibilityInitialize()
{
	compatibilityState.requested = r_neuralCompatibilityEnable.GetBool();
	if( !compatibilityState.requested )
	{
		compatibilityState.result = "disabled";
		return false;
	}
	if( compatibilityState.initialized )
	{
		return true;
	}

#if !defined( _WIN32 )
	compatibilityState.result = "Windows only";
	common->Warning( "r_neuralCompatibilityEnable is currently supported only on Windows/D3D12" );
	return false;
#else
	if( HMODULE existing = FindLoadedReShade() )
	{
		compatibilityState.module = existing;
		compatibilityState.existingRuntime = true;
		compatibilityState.initialized = true;
		compatibilityState.result = "existing ReShade runtime";
		compatibilityState.profileApplied = ApplyCompatibilityProfile( existing );
		common->Printf( "Neural compatibility: using the ReShade runtime already loaded by the process\n" );
		return true;
	}

	wchar_t runtimePath[MAX_OSPATH];
	if( !BuildRuntimePath( runtimePath, _countof( runtimePath ) ) )
	{
		compatibilityState.result = "invalid runtime path";
		common->Warning( "Could not resolve r_neuralCompatibilityRuntime '%s'", r_neuralCompatibilityRuntime.GetString() );
		return false;
	}

	// The renamed runtime is loaded deliberately by NeuralDoom. ReShade's normal
	// graphics hooks remain enabled so it can provide its complete API objects and
	// lifecycle events to the external add-on without acting as a DXGI proxy.
	compatibilityState.module = LoadLibraryExW( runtimePath, NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS );
	if( compatibilityState.module == NULL )
	{
		compatibilityState.result = "runtime load failed";
		common->Warning( "Could not load the local neural compatibility runtime '%s' (Windows error %u)", r_neuralCompatibilityRuntime.GetString(), GetLastError() );
		return false;
	}

	HMODULE runtimeModule = static_cast<HMODULE>( compatibilityState.module );
	if( GetProcAddress( runtimeModule, "ReShadeVersion" ) == NULL ||
		GetProcAddress( runtimeModule, "ReShadeRegisterAddon" ) == NULL )
	{
		compatibilityState.result = "not a ReShade add-on runtime";
		common->Warning( "The local compatibility runtime '%s' does not expose the required ReShade add-on API", r_neuralCompatibilityRuntime.GetString() );
		FreeLibrary( runtimeModule );
		compatibilityState.module = NULL;
		return false;
	}

	compatibilityState.profileApplied = ApplyCompatibilityProfile( runtimeModule );
	compatibilityState.initialized = true;
	compatibilityState.result = "explicit runtime loaded";
	common->Printf( "Neural compatibility: explicitly loaded '%s' before D3D12 device creation\n", r_neuralCompatibilityRuntime.GetString() );
	return true;
#endif
}

void R_NeuralCompatibilityStatus_f( const idCmdArgs& args )
{
	(void)args;
	common->Printf( "Neural compatibility: requested %s, initialized %s, source %s, profile %s (%s)\n",
		compatibilityState.requested ? "yes" : "no",
		compatibilityState.initialized ? "yes" : "no",
		compatibilityState.existingRuntime ? "existing process runtime" : r_neuralCompatibilityRuntime.GetString(),
		r_neuralCompatibilityProfile.GetString()[0] != '\0' ? r_neuralCompatibilityProfile.GetString() : "reshade.ini",
		compatibilityState.profileApplied ? "applied" : compatibilityState.result );
}
