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
idCVar r_streamlineApplicationId( "r_streamlineApplicationId", "0", CVAR_RENDERER | CVAR_INTEGER | CVAR_INIT | CVAR_NEW, "optional NVIDIA-issued application ID; 0 uses the experimental custom-engine identity" );
idCVar r_neuralDLSSQuality( "r_neuralDLSSQuality", "0", CVAR_RENDERER | CVAR_INTEGER | CVAR_ARCHIVE, "DLSS scaling preset: 0 Quality, 1 Balanced, 2 Performance; only with r_neuralBackend 3", 0, 2 );

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
	streamlineState.dlssRequested = true;

	sl::Feature features[] = { sl::kFeatureDLSS };
	sl::Preferences preferences = {};
	preferences.flags = sl::PreferenceFlags::eDisableCLStateTracking |
						sl::PreferenceFlags::eUseManualHooking |
						sl::PreferenceFlags::eUseFrameBasedResourceTagging;
	preferences.engine = sl::EngineType::eCustom;
	preferences.engineVersion = ENGINE_VERSION;
	preferences.projectId = "6f2c79d0-5c63-4e48-a129-5db818b387b8";
	preferences.renderAPI = sl::RenderAPI::eD3D12;
	preferences.applicationId = streamlineState.applicationId;
	preferences.featuresToLoad = features;
	preferences.numFeaturesToLoad = 1;

	const sl::Result result = slInit( preferences );
	streamlineState.initializeResult = sl::getResultAsStr( result );
	streamlineState.initialized = result == sl::Result::eOk;
	if( !streamlineState.initialized )
	{
		common->Warning( "Streamline initialization failed: %s; continuing with the native renderer", streamlineState.initializeResult );
		return false;
	}

	common->Printf( "Streamline initialized with DLSS requested (%s identity)\n",
		streamlineState.applicationId > 0 ? "NVIDIA application ID" : "experimental custom-engine" );
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

	ID3D12Device* d3dDevice = static_cast<ID3D12Device*>( nativeDevice );
	LUID adapterLuid = d3dDevice->GetAdapterLuid();
	sl::AdapterInfo adapterInfo = {};
	adapterInfo.deviceLUID = reinterpret_cast<uint8_t*>( &adapterLuid );
	adapterInfo.deviceLUIDSizeInBytes = sizeof( adapterLuid );
	const sl::Result supportResult = slIsFeatureSupported( sl::kFeatureDLSS, adapterInfo );
	streamlineState.dlssResult = sl::getResultAsStr( supportResult );
	streamlineState.dlssSupported = supportResult == sl::Result::eOk;

	common->Printf( "Streamline accepted the native D3D12 device; DLSS %s\n",
		streamlineState.dlssSupported ? "supported" : streamlineState.dlssResult );
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

bool R_StreamlineIsDLSSSupported()
{
	return streamlineState.dlssSupported;
}

int R_StreamlineDLSSQuality()
{
	return idMath::ClampInt( 0, 2, r_neuralDLSSQuality.GetInteger() );
}

const char* R_StreamlineDLSSQualityName()
{
	const char* names[] = { "Quality", "Balanced", "Performance" };
	return names[R_StreamlineDLSSQuality()];
}

bool R_StreamlineDLSSRenderSize( int outputWidth, int outputHeight, int& renderWidth, int& renderHeight, int quality )
{
#if USE_STREAMLINE
	if( !R_StreamlineIsDLSSSupported() || outputWidth <= 0 || outputHeight <= 0 ) { return false; }
	// Frontend-owned cache: query the SDK again when the window or preset changes.
	static int cachedWidth = 0, cachedHeight = 0, cachedQuality = -1, width = 0, height = 0;
	quality = idMath::ClampInt( 0, 2, quality );
	if( cachedWidth != outputWidth || cachedHeight != outputHeight || cachedQuality != quality )
	{
		sl::DLSSOptions options = {};
		const sl::DLSSMode modes[] = { sl::DLSSMode::eMaxQuality, sl::DLSSMode::eBalanced, sl::DLSSMode::eMaxPerformance };
		options.mode = modes[quality];
		options.outputWidth = outputWidth;
		options.outputHeight = outputHeight;
		sl::DLSSOptimalSettings settings = {};
		if( slDLSSGetOptimalSettings( options, settings ) != sl::Result::eOk || settings.optimalRenderWidth == 0 || settings.optimalRenderHeight == 0 || settings.optimalRenderWidth > uint32( outputWidth ) || settings.optimalRenderHeight > uint32( outputHeight ) ) { return false; }
		cachedWidth = outputWidth; cachedHeight = outputHeight; cachedQuality = quality;
		width = settings.optimalRenderWidth; height = settings.optimalRenderHeight;
	}
	renderWidth = width; renderHeight = height;
	return true;
#else
	(void)outputWidth; (void)outputHeight; (void)renderWidth; (void)renderHeight; (void)quality;
	return false;
#endif
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
		streamlineState.applicationId > 0 ? "NVIDIA application ID" : "experimental custom-engine" );
	common->Printf( "Streamline results: init %s, device %s, DLSS %s\n",
		streamlineState.initializeResult,
		streamlineState.deviceResult,
		streamlineState.dlssResult );
}
