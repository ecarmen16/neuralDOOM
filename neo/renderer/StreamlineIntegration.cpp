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
#include "StreamlineIntegration.h"

#if USE_STREAMLINE
	#include <d3d12.h>
	#include <sl.h>
	#include <sl_dlss.h>
	#include <sl_helpers.h>
#endif

idCVar r_streamlineEnable( "r_streamlineEnable", "0", CVAR_RENDERER | CVAR_BOOL | CVAR_INIT | CVAR_NEW, "initialize the optional local NVIDIA Streamline runtime at startup" );
idCVar r_streamlineApplicationId( "r_streamlineApplicationId", "0", CVAR_RENDERER | CVAR_INTEGER | CVAR_INIT | CVAR_NEW, "NVIDIA-issued application ID used to request NGX/DLSS; 0 initializes Streamline core only" );

namespace
{
	struct streamlineState_t
	{
		bool compiled = false;
		bool requested = false;
		bool initialized = false;
		bool deviceSet = false;
		bool dlssRequested = false;
		bool dlssSupported = false;
		int applicationId = 0;
		const char* initializeResult = "not attempted";
		const char* deviceResult = "not attempted";
		const char* dlssResult = "not requested";
	};

	streamlineState_t streamlineState;
}

bool R_StreamlineInitialize()
{
	streamlineState = streamlineState_t();
	streamlineState.requested = r_streamlineEnable.GetBool();

#if !USE_STREAMLINE
	streamlineState.initializeResult = streamlineState.requested ? "SDK not compiled" : "disabled";
	if( streamlineState.requested )
	{
		common->Warning( "r_streamlineEnable requested, but this executable was built with USE_STREAMLINE=OFF" );
	}
	return false;
#else
	streamlineState.compiled = true;
	if( !streamlineState.requested )
	{
		streamlineState.initializeResult = "disabled";
		return false;
	}

	streamlineState.applicationId = r_streamlineApplicationId.GetInteger();
	streamlineState.dlssRequested = streamlineState.applicationId > 0;

	sl::Feature features[] = { sl::kFeatureDLSS };
	sl::Preferences preferences = {};
	preferences.flags = sl::PreferenceFlags::eDisableCLStateTracking |
						sl::PreferenceFlags::eUseManualHooking |
						sl::PreferenceFlags::eUseFrameBasedResourceTagging;
	preferences.engine = sl::EngineType::eCustom;
	preferences.engineVersion = ENGINE_VERSION;
	preferences.renderAPI = sl::RenderAPI::eD3D12;
	preferences.applicationId = streamlineState.applicationId;
	if( streamlineState.dlssRequested )
	{
		preferences.featuresToLoad = features;
		preferences.numFeaturesToLoad = 1;
	}

	const sl::Result result = slInit( preferences );
	streamlineState.initializeResult = sl::getResultAsStr( result );
	streamlineState.initialized = result == sl::Result::eOk;
	if( !streamlineState.initialized )
	{
		common->Warning( "Streamline initialization failed: %s; continuing with the native renderer", streamlineState.initializeResult );
		return false;
	}

	common->Printf( "Streamline initialized in %s mode%s\n",
		streamlineState.dlssRequested ? "DLSS-requested" : "core-only",
		streamlineState.dlssRequested ? "" : "; set an NVIDIA-issued r_streamlineApplicationId at startup to request DLSS" );
	return true;
#endif
}

bool R_StreamlineSetD3DDevice( void* nativeDevice )
{
#if !USE_STREAMLINE
	(void)nativeDevice;
	return false;
#else
	if( !streamlineState.initialized || nativeDevice == NULL )
	{
		streamlineState.deviceResult = nativeDevice == NULL ? "null native device" : "not initialized";
		return false;
	}

	const sl::Result deviceResult = slSetD3DDevice( nativeDevice );
	streamlineState.deviceResult = sl::getResultAsStr( deviceResult );
	streamlineState.deviceSet = deviceResult == sl::Result::eOk;
	if( !streamlineState.deviceSet )
	{
		common->Warning( "Streamline rejected the D3D12 device: %s; DLSS remains disabled", streamlineState.deviceResult );
		return false;
	}

	if( streamlineState.dlssRequested )
	{
		ID3D12Device* d3dDevice = static_cast<ID3D12Device*>( nativeDevice );
		LUID adapterLuid = d3dDevice->GetAdapterLuid();
		sl::AdapterInfo adapterInfo = {};
		adapterInfo.deviceLUID = reinterpret_cast<uint8_t*>( &adapterLuid );
		adapterInfo.deviceLUIDSizeInBytes = sizeof( adapterLuid );
		const sl::Result supportResult = slIsFeatureSupported( sl::kFeatureDLSS, adapterInfo );
		streamlineState.dlssResult = sl::getResultAsStr( supportResult );
		streamlineState.dlssSupported = supportResult == sl::Result::eOk;
	}

	common->Printf( "Streamline accepted the native D3D12 device; DLSS %s\n",
		streamlineState.dlssRequested ? ( streamlineState.dlssSupported ? "supported" : streamlineState.dlssResult ) : "not requested" );
	return true;
#endif
}

void R_StreamlineShutdown()
{
#if USE_STREAMLINE
	if( streamlineState.initialized )
	{
		const sl::Result result = slShutdown();
		if( result != sl::Result::eOk )
		{
			common->Warning( "Streamline shutdown failed: %s", sl::getResultAsStr( result ) );
		}
	}
#endif
	streamlineState.initialized = false;
	streamlineState.deviceSet = false;
	streamlineState.dlssSupported = false;
}

bool R_StreamlineIsInitialized()
{
	return streamlineState.initialized;
}

bool R_StreamlineIsDLSSRequested()
{
	return streamlineState.dlssRequested;
}

void R_StreamlineStatus_f( const idCmdArgs& args )
{
	(void)args;
	common->Printf( "Streamline: compiled %s, requested %s, initialized %s, device %s\n",
		streamlineState.compiled ? "yes" : "no",
		streamlineState.requested ? "yes" : "no",
		streamlineState.initialized ? "yes" : "no",
		streamlineState.deviceSet ? "set" : "unset" );
	common->Printf( "Streamline identity: applicationId %d, mode %s\n",
		streamlineState.applicationId,
		streamlineState.dlssRequested ? "DLSS-requested" : "core-only/fallback" );
	common->Printf( "Streamline results: init %s, device %s, DLSS %s\n",
		streamlineState.initializeResult,
		streamlineState.deviceResult,
		streamlineState.dlssResult );
}
