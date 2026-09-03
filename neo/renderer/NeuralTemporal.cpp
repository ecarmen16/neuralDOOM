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

		const bool valid = initialized && frame.commandList != NULL && frame.sceneColorHDR && frame.depth && frame.motionVectors && frame.reactiveMask && frame.transparencyMask && frame.output && frame.exposure && frame.renderWidth > 0 && frame.renderHeight > 0 && frame.renderSampleCount > 0 && frame.outputWidth > 0 && frame.outputHeight > 0 && frame.cameraNear > 0.0f && frame.cameraFar > frame.cameraNear && frame.cameraVerticalFov > 0.0f && frame.cameraAspectRatio > 0.0f && frame.motionVectorsValid && frame.masksValid && frame.exposureBufferValid;
		if( !valid )
		{
			rejectedFrames++;
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
