/*
===========================================================================

Doom 3 BFG Edition GPL Source Code

This file is part of the Doom 3 BFG Edition Source Code and is distributed
under the GNU General Public License version 3 and the additional terms that
apply to this source tree.

===========================================================================
*/

#include "precompiled.h"
#pragma hdrstop

#include "NeuralTemporal.h"
#include "RenderCommon.h"
#include "StreamlineIntegration.h"

#if USE_STREAMLINE
	#include <d3d12.h>
	#include <sl.h>
	#include <sl_dlss.h>
	#include <sl_helpers.h>
#endif

class idStreamlineNeuralTemporalBackend : public idNeuralTemporalBackend
{
public:
	idStreamlineNeuralTemporalBackend() : initialized( false ), optionsDirty( true ), resetPending( true ), evaluatedFrames( 0 ), presentedFrames( 0 ), rejectedFrames( 0 ), lastEpoch( 0 ), lastFrameIndex( 0 ), configuredMode( 0 ), renderWidth( 0 ), renderHeight( 0 ), outputWidth( 0 ), outputHeight( 0 ), lastResult( "not attempted" ) {}

	virtual bool Initialize( nvrhi::IDevice* device ) override
	{
#if USE_STREAMLINE
		initialized = device != NULL && device->getGraphicsAPI() == nvrhi::GraphicsAPI::D3D12 && R_StreamlineIsInitialized() && R_StreamlineIsDLSSSupported();
		lastResult = initialized ? "ready" : "Streamline/DLSS unavailable";
#else
		(void)device;
		lastResult = "USE_STREAMLINE=OFF";
#endif
		return initialized;
	}

	virtual void Shutdown() override
	{
		initialized = false;
	}

	virtual void Resize( int newRenderWidth, int newRenderHeight, int newOutputWidth, int newOutputHeight ) override
	{
		renderWidth = newRenderWidth;
		renderHeight = newRenderHeight;
		outputWidth = newOutputWidth;
		outputHeight = newOutputHeight;
		optionsDirty = true;
		resetPending = true;
	}

	virtual void ResetHistory( uint64 historyEpoch ) override
	{
		lastEpoch = historyEpoch;
		resetPending = true;
	}

	virtual bool Evaluate( const neuralTemporalFrame_t& frame ) override
	{
		evaluatedFrames++;
		lastEpoch = frame.historyEpoch;

#if !USE_STREAMLINE
		(void)frame;
		rejectedFrames++;
		return false;
#else
		const int requestedMode = r_neuralBackend.GetInteger();
		const bool nativeDLAA = requestedMode == 2;
		const bool qualityDLSS = requestedMode == 3;
		const bool valid = initialized && ( nativeDLAA || qualityDLSS ) && frame.commandList != NULL && frame.sceneColorHDR && frame.depth && frame.motionVectors && frame.reactiveMask && frame.transparencyMask && frame.output && frame.renderWidth > 0 && frame.renderHeight > 0 && frame.renderWidth <= frame.outputWidth && frame.renderHeight <= frame.outputHeight && frame.renderSampleCount == 1 && ( !nativeDLAA || ( frame.renderWidth == frame.outputWidth && frame.renderHeight == frame.outputHeight ) ) && frame.motionVectorsValid && frame.masksValid;
		if( !valid )
		{
			rejectedFrames++;
			lastResult = "invalid or non-native frame contract";
			return false;
		}
		if( presentedFrames > 0 && frame.frameIndex != lastFrameIndex + 1 )
		{
			resetPending = true;
		}
		if( configuredMode != requestedMode || outputWidth != frame.outputWidth || outputHeight != frame.outputHeight )
		{
			optionsDirty = true;
			resetPending = true;
		}

		if( optionsDirty )
		{
			sl::DLSSOptions options = {};
			options.mode = nativeDLAA ? sl::DLSSMode::eDLAA : sl::DLSSMode::eMaxQuality;
			options.outputWidth = frame.outputWidth;
			options.outputHeight = frame.outputHeight;
			options.preExposure = 1.0f;
			options.exposureScale = frame.exposureScale;
			options.colorBuffersHDR = sl::Boolean::eTrue;
			options.dlaaPreset = sl::DLSSPreset::ePresetK;
			options.qualityPreset = sl::DLSSPreset::ePresetK;
			options.useAutoExposure = sl::Boolean::eTrue;
			options.alphaUpscalingEnabled = sl::Boolean::eFalse;
			const sl::Result optionsResult = slDLSSSetOptions( sl::ViewportHandle( 0 ), options );
			if( optionsResult != sl::Result::eOk )
			{
				return Reject( "slDLSSSetOptions", optionsResult );
			}
			optionsDirty = false;
			configuredMode = requestedMode;
		}
		renderWidth = frame.renderWidth;
		renderHeight = frame.renderHeight;
		outputWidth = frame.outputWidth;
		outputHeight = frame.outputHeight;

		sl::FrameToken* frameToken = NULL;
		const sl::Result tokenResult = slGetNewFrameToken( frameToken, &frame.frameIndex );
		if( tokenResult != sl::Result::eOk || frameToken == NULL )
		{
			return Reject( "slGetNewFrameToken", tokenResult );
		}

		idRenderMatrix inverseProjection;
		idRenderMatrix inverseCurrentViewProjection;
		idRenderMatrix clipToPrevClip;
		idRenderMatrix prevClipToClip;
		if( !idRenderMatrix::Inverse( frame.cameraViewToClip, inverseProjection ) || !idRenderMatrix::Inverse( frame.currentViewProjection, inverseCurrentViewProjection ) )
		{
			rejectedFrames++;
			lastResult = "matrix inversion failed";
			return false;
		}
		idRenderMatrix::Multiply( frame.previousViewProjection, inverseCurrentViewProjection, clipToPrevClip );
		if( !idRenderMatrix::Inverse( clipToPrevClip, prevClipToClip ) )
		{
			rejectedFrames++;
			lastResult = "reprojection inversion failed";
			return false;
		}

		sl::Constants constants = {};
		CopyMatrix( frame.cameraViewToClip, constants.cameraViewToClip );
		CopyMatrix( inverseProjection, constants.clipToCameraView );
		CopyMatrix( clipToPrevClip, constants.clipToPrevClip );
		CopyMatrix( prevClipToClip, constants.prevClipToClip );
		constants.jitterOffset = sl::float2( frame.currentJitterPixels.x, frame.currentJitterPixels.y );
		constants.mvecScale = sl::float2( 1.0f / frame.renderWidth, 1.0f / frame.renderHeight );
		constants.cameraPinholeOffset = sl::float2( 0.0f, 0.0f );
		constants.cameraPos = ToFloat3( frame.cameraPosition );
		constants.cameraFwd = ToFloat3( frame.cameraForward );
		constants.cameraRight = ToFloat3( frame.cameraRight );
		constants.cameraUp = ToFloat3( frame.cameraUp );
		constants.cameraNear = frame.cameraNear;
		constants.cameraFar = frame.cameraFar;
		constants.cameraFOV = frame.cameraVerticalFov;
		constants.cameraAspectRatio = frame.cameraAspectRatio;
		constants.motionVectorsInvalidValue = FLT_MIN;
		constants.depthInverted = sl::Boolean::eFalse;
		constants.cameraMotionIncluded = sl::Boolean::eTrue;
		constants.motionVectors3D = sl::Boolean::eFalse;
		constants.reset = ( resetPending || frame.resetHistory ) ? sl::Boolean::eTrue : sl::Boolean::eFalse;
		constants.orthographicProjection = sl::Boolean::eFalse;
		constants.motionVectorsDilated = sl::Boolean::eFalse;
		constants.motionVectorsJittered = sl::Boolean::eFalse;

		frame.commandList->setTextureState( frame.sceneColorHDR.Get(), nvrhi::AllSubresources, nvrhi::ResourceStates::ShaderResource );
		frame.commandList->setTextureState( frame.depth.Get(), nvrhi::AllSubresources, nvrhi::ResourceStates::ShaderResource );
		frame.commandList->setTextureState( frame.motionVectors.Get(), nvrhi::AllSubresources, nvrhi::ResourceStates::ShaderResource );
		frame.commandList->setTextureState( frame.reactiveMask.Get(), nvrhi::AllSubresources, nvrhi::ResourceStates::ShaderResource );
		frame.commandList->setTextureState( frame.transparencyMask.Get(), nvrhi::AllSubresources, nvrhi::ResourceStates::ShaderResource );
		frame.commandList->setTextureState( frame.output.Get(), nvrhi::AllSubresources, nvrhi::ResourceStates::UnorderedAccess );
		frame.commandList->commitBarriers();

		const D3D12_RESOURCE_STATES shaderResourceState = D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE;
		sl::Resource inputColor = MakeResource( frame.sceneColorHDR.Get(), shaderResourceState );
		sl::Resource depth = MakeResource( frame.depth.Get(), shaderResourceState );
		sl::Resource motionVectors = MakeResource( frame.motionVectors.Get(), shaderResourceState );
		sl::Resource reactiveMask = MakeResource( frame.reactiveMask.Get(), shaderResourceState );
		sl::Resource transparencyMask = MakeResource( frame.transparencyMask.Get(), shaderResourceState );
		sl::Resource output = MakeResource( frame.output.Get(), D3D12_RESOURCE_STATE_UNORDERED_ACCESS );
		sl::Extent renderExtent = { 0, 0, uint32( frame.renderWidth ), uint32( frame.renderHeight ) };
		sl::Extent outputExtent = { 0, 0, uint32( frame.outputWidth ), uint32( frame.outputHeight ) };
		sl::ResourceTag tags[] =
		{
			sl::ResourceTag( &inputColor, sl::kBufferTypeScalingInputColor, sl::ResourceLifecycle::eValidUntilEvaluate, &renderExtent ),
			sl::ResourceTag( &output, sl::kBufferTypeScalingOutputColor, sl::ResourceLifecycle::eValidUntilEvaluate, &outputExtent ),
			sl::ResourceTag( &depth, sl::kBufferTypeDepth, sl::ResourceLifecycle::eValidUntilEvaluate, &renderExtent ),
			sl::ResourceTag( &motionVectors, sl::kBufferTypeMotionVectors, sl::ResourceLifecycle::eValidUntilEvaluate, &renderExtent ),
			sl::ResourceTag( &reactiveMask, sl::kBufferTypeReactiveMaskHint, sl::ResourceLifecycle::eValidUntilEvaluate, &renderExtent ),
			sl::ResourceTag( &transparencyMask, sl::kBufferTypeTransparencyAndCompositionMaskHint, sl::ResourceLifecycle::eValidUntilEvaluate, &renderExtent )
		};

		void* nativeCommandList = frame.commandList->getNativeObject( nvrhi::ObjectTypes::D3D12_GraphicsCommandList );
		if( nativeCommandList == NULL )
		{
			rejectedFrames++;
			lastResult = "native D3D12 command list unavailable";
			return false;
		}

		const sl::ViewportHandle viewport( 0 );
		sl::Result result = slSetConstants( constants, *frameToken, viewport );
		if( result != sl::Result::eOk )
		{
			return Reject( "slSetConstants", result );
		}
		result = slSetTagForFrame( *frameToken, viewport, tags, sizeof( tags ) / sizeof( tags[0] ), nativeCommandList );
		if( result != sl::Result::eOk )
		{
			return Reject( "slSetTagForFrame", result );
		}

		const sl::BaseStructure* inputs[] = { &viewport };
		result = slEvaluateFeature( sl::kFeatureDLSS, *frameToken, inputs, sizeof( inputs ) / sizeof( inputs[0] ), nativeCommandList );
		frame.commandList->clearState();
		if( result != sl::Result::eOk )
		{
			return Reject( "slEvaluateFeature", result );
		}

		resetPending = false;
		lastFrameIndex = frame.frameIndex;
		presentedFrames++;
		lastResult = nativeDLAA ? "DLAA evaluated" : "DLSS Quality evaluated";
		return true;
#endif
	}

	virtual void PrintStatus() const override
	{
		common->Printf( "Neural temporal backend: Streamline DLSS, initialized %s, evaluated %llu, presented %llu, rejected %llu, epoch %llu, render %dx%d, output %dx%d, last %s\n",
			initialized ? "yes" : "no", evaluatedFrames, presentedFrames, rejectedFrames, lastEpoch, renderWidth, renderHeight, outputWidth, outputHeight, lastResult );
	}

private:
#if USE_STREAMLINE
	static void CopyMatrix( const idRenderMatrix& source, sl::float4x4& destination )
	{
		for( int row = 0; row < 4; row++ )
		{
			destination.setRow( row, sl::float4( source[row][0], source[row][1], source[row][2], source[row][3] ) );
		}
	}

	static sl::float3 ToFloat3( const idVec3& value )
	{
		return sl::float3( value.x, value.y, value.z );
	}

	static sl::Resource MakeResource( nvrhi::ITexture* texture, D3D12_RESOURCE_STATES state )
	{
		return sl::Resource( sl::ResourceType::eTex2d, texture->getNativeObject( nvrhi::ObjectTypes::D3D12_Resource ), nullptr, nullptr, uint32( state ) );
	}

	bool Reject( const char* operation, sl::Result result )
	{
		rejectedFrames++;
		lastResult = sl::getResultAsStr( result );
		if( rejectedFrames == 1 )
		{
			common->Warning( "Streamline DLAA %s failed: %s; using native TAA fallback", operation, lastResult );
		}
		return false;
	}
#endif

	bool		initialized;
	bool		optionsDirty;
	bool		resetPending;
	uint64		evaluatedFrames;
	uint64		presentedFrames;
	uint64		rejectedFrames;
	uint64		lastEpoch;
	uint32		lastFrameIndex;
	int			configuredMode;
	int			renderWidth;
	int			renderHeight;
	int			outputWidth;
	int			outputHeight;
	const char*	lastResult;
};

idNeuralTemporalBackend* R_CreateStreamlineNeuralTemporalBackend()
{
	return new idStreamlineNeuralTemporalBackend();
}
