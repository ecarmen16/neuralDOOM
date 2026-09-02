/*
===========================================================================

Doom 3 BFG Edition GPL Source Code

This file is part of the Doom 3 BFG Edition Source Code and is distributed
under the GNU General Public License version 3 and the additional terms that
apply to this source tree.

===========================================================================
*/

#ifndef __RENDERER_NEURAL_TEMPORAL_H__
#define __RENDERER_NEURAL_TEMPORAL_H__

#include <nvrhi/nvrhi.h>

enum neuralMotionVectorConvention_t
{
	NMVC_PREVIOUS_MINUS_CURRENT_PIXELS
};

enum neuralDepthConvention_t
{
	NDC_DEVICE_ZERO_TO_ONE_NON_REVERSED
};

struct neuralTemporalFrame_t
{
	nvrhi::ICommandList*		commandList;
	nvrhi::TextureHandle		sceneColorHDR;
	nvrhi::TextureHandle		depth;
	nvrhi::TextureHandle		motionVectors;
	nvrhi::TextureHandle		reactiveMask;
	nvrhi::TextureHandle		transparencyMask;
	nvrhi::TextureHandle		output;
	nvrhi::BufferHandle		exposure;

	idRenderMatrix			currentViewProjection;
	idRenderMatrix			previousViewProjection;
	idVec2					currentJitterPixels;
	idVec2					previousJitterPixels;

	float					exposureScale;
	int						renderWidth;
	int						renderHeight;
	int						renderSampleCount;
	int						outputWidth;
	int						outputHeight;
	int						stereoEye;
	uint64					historyEpoch;
	neuralMotionVectorConvention_t motionVectorConvention;
	neuralDepthConvention_t	depthConvention;

	bool					resetHistory;
	bool					motionVectorsValid;
	bool					masksValid;
	bool					viewmodelIncluded;
	bool					exposureIsAutomatic;
	bool					exposureBufferValid;
};

class idNeuralTemporalBackend
{
public:
	virtual ~idNeuralTemporalBackend() {}

	virtual bool Initialize( nvrhi::IDevice* device ) = 0;
	virtual void Shutdown() = 0;
	virtual void Resize( int renderWidth, int renderHeight, int outputWidth, int outputHeight ) = 0;
	virtual void ResetHistory( uint64 historyEpoch ) = 0;
	virtual bool Evaluate( const neuralTemporalFrame_t& frame ) = 0;
	virtual void PrintStatus() const = 0;
};

idNeuralTemporalBackend* R_CreateNullNeuralTemporalBackend();

#endif
