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

const char* R_ValidateNeuralTemporalFrame( const neuralTemporalFrame_t& frame )
{
	if( frame.commandList == NULL || !frame.sceneColorHDR || !frame.depth || !frame.motionVectors || !frame.reactiveMask || !frame.transparencyMask || !frame.output || !frame.exposure )
	{
		return "missing frame resource";
	}
	if( frame.renderWidth <= 0 || frame.renderHeight <= 0 || frame.outputWidth <= 0 || frame.outputHeight <= 0 || frame.renderWidth > frame.outputWidth || frame.renderHeight > frame.outputHeight || frame.renderSampleCount != 1 )
	{
		return "invalid frame extents or sample count";
	}
	if( !frame.motionVectorsValid || !frame.masksValid || !frame.exposureBufferValid || frame.motionVectorConvention != NMVC_PREVIOUS_MINUS_CURRENT_PIXELS || frame.depthConvention != NDC_DEVICE_ZERO_TO_ONE_NON_REVERSED )
	{
		return "invalid input validity or coordinate convention";
	}
	const float scalars[] = { frame.cameraNear, frame.cameraFar, frame.cameraVerticalFov, frame.cameraAspectRatio, frame.exposureScale, frame.currentJitterPixels.x, frame.currentJitterPixels.y, frame.previousJitterPixels.x, frame.previousJitterPixels.y };
	for( int i = 0; i < sizeof( scalars ) / sizeof( scalars[0] ); i++ )
	{
		if( IEEE_FLT_IS_INF_NAN( scalars[i] ) )
		{
			return "nonfinite camera, jitter or exposure";
		}
	}
	if( frame.cameraNear <= 0.0f || frame.cameraFar <= frame.cameraNear || frame.cameraVerticalFov <= 0.0f || frame.cameraVerticalFov >= idMath::PI || frame.cameraAspectRatio <= 0.0f || frame.exposureScale <= 0.0f )
	{
		return "camera or exposure out of range";
	}
	const idRenderMatrix* matrices[] = { &frame.currentViewProjection, &frame.previousViewProjection, &frame.cameraViewToClip };
	for( int i = 0; i < 3; i++ )
	{
		for( int j = 0; j < 16; j++ )
		{
			if( IEEE_FLT_IS_INF_NAN( ( *matrices[i] )[j / 4][j % 4] ) )
			{
				return "nonfinite camera matrix";
			}
		}
	}
	const idVec3 vectors[] = { frame.cameraPosition, frame.cameraForward, frame.cameraRight, frame.cameraUp };
	for( int i = 0; i < 4; i++ )
	{
		for( int j = 0; j < 3; j++ )
		{
			if( IEEE_FLT_IS_INF_NAN( vectors[i][j] ) )
			{
				return "nonfinite camera vector";
			}
		}
	}
	const nvrhi::TextureHandle textures[] = { frame.sceneColorHDR, frame.depth, frame.motionVectors, frame.reactiveMask, frame.transparencyMask, frame.output };
	for( int i = 0; i < 6; i++ )
	{
		const nvrhi::TextureDesc& desc = textures[i]->getDesc();
		const int width = i == 5 ? frame.outputWidth : frame.renderWidth;
		const int height = i == 5 ? frame.outputHeight : frame.renderHeight;
		// Inputs can occupy a smaller viewport within native-resolution storage.
		if( desc.width < uint32( width ) || desc.height < uint32( height ) || desc.sampleCount != 1 || desc.dimension != nvrhi::TextureDimension::Texture2D )
		{
			return "texture extent, dimension or samples mismatch";
		}
	}
	const nvrhi::Format depthFormat = frame.depth->getDesc().format;
	if( frame.sceneColorHDR->getDesc().format != nvrhi::Format::RGBA16_FLOAT || frame.output->getDesc().format != nvrhi::Format::RGBA16_FLOAT || frame.motionVectors->getDesc().format != nvrhi::Format::RG16_FLOAT || frame.reactiveMask->getDesc().format != nvrhi::Format::R8_UNORM || frame.transparencyMask->getDesc().format != nvrhi::Format::R8_UNORM || ( depthFormat != nvrhi::Format::D24S8 && depthFormat != nvrhi::Format::D32S8 ) )
	{
		return "texture format mismatch";
	}
	if( frame.exposure->getDesc().byteSize < sizeof( uint32 ) || frame.sceneColorHDR == frame.output )
	{
		return "invalid exposure storage or aliased output";
	}
	return NULL;
}

class idNullNeuralTemporalBackend : public idNeuralTemporalBackend
{
public:
	idNullNeuralTemporalBackend() : initialized( false ), evaluatedFrames( 0 ), rejectedFrames( 0 ), lastEpoch( 0 ), lastResetEpoch( 0 ), renderWidth( 0 ), renderHeight( 0 ), outputWidth( 0 ), outputHeight( 0 ) {}

	virtual bool Initialize( nvrhi::IDevice* device ) override
	{
		initialized = device != NULL;
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
	}

	virtual void ResetHistory( uint64 historyEpoch ) override
	{
		lastResetEpoch = historyEpoch;
	}

	virtual bool Evaluate( const neuralTemporalFrame_t& frame ) override
	{
		evaluatedFrames++;
		lastEpoch = frame.historyEpoch;

		const char* error = initialized ? R_ValidateNeuralTemporalFrame( frame ) : "backend not initialized";
		if( error != NULL )
		{
			rejectedFrames++;
			if( rejectedFrames == 1 )
			{
				common->Warning( "Neural temporal contract rejected: %s", error );
			}
		}

		// The null/debug backend validates and consumes the complete contract but
		// deliberately declines presentation so the established TAA path remains active.
		return false;
	}

	virtual void PrintStatus() const override
	{
		common->Printf( "Neural temporal backend: null/debug, initialized %s, evaluated %llu, rejected %llu, epoch %llu, lastResetEpoch %llu, render %dx%d, output %dx%d\n",
			initialized ? "yes" : "no", evaluatedFrames, rejectedFrames, lastEpoch, lastResetEpoch, renderWidth, renderHeight, outputWidth, outputHeight );
	}

private:
	bool	initialized;
	uint64	evaluatedFrames;
	uint64	rejectedFrames;
	uint64	lastEpoch;
	uint64	lastResetEpoch;
	int		renderWidth;
	int		renderHeight;
	int		outputWidth;
	int		outputHeight;
};

idNeuralTemporalBackend* R_CreateNullNeuralTemporalBackend()
{
	return new idNullNeuralTemporalBackend();
}
