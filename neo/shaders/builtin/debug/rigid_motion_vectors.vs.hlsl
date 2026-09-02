/*
===========================================================================

Doom 3 BFG Edition GPL Source Code

This file is part of the Doom 3 BFG Edition Source Code and is distributed
under the GNU General Public License version 3 and the additional terms that
apply to this source tree.

===========================================================================
*/

#include "global_inc.hlsl"
#include "renderParmSet6.inc.hlsl"

#if USE_GPU_SKINNING
StructuredBuffer<float4> matrices : register(t11);
StructuredBuffer<float4> previousMatrices : register(t12);
#endif

struct VS_IN
{
	float4 position : POSITION;
	float2 texcoord : TEXCOORD0;
	float4 normal : NORMAL;
	float4 tangent : TANGENT;
	float4 color : COLOR0;
	float4 color2 : COLOR1;
};

struct VS_OUT
{
	float4 position : SV_Position;
	float4 previousClipPosition : TEXCOORD0;
};

void main( VS_IN vertex, out VS_OUT result )
{
#if USE_GPU_SKINNING
	const float w0 = vertex.color2.x;
	const float w1 = vertex.color2.y;
	const float w2 = vertex.color2.z;
	const float w3 = vertex.color2.w;

	int joint = int( vertex.color.x * 255.1 * 3.0 );
	float4 matX = matrices[int( joint + 0 )] * w0;
	float4 matY = matrices[int( joint + 1 )] * w0;
	float4 matZ = matrices[int( joint + 2 )] * w0;
	float4 previousMatX = previousMatrices[int( joint + 0 )] * w0;
	float4 previousMatY = previousMatrices[int( joint + 1 )] * w0;
	float4 previousMatZ = previousMatrices[int( joint + 2 )] * w0;

	joint = int( vertex.color.y * 255.1 * 3.0 );
	matX += matrices[int( joint + 0 )] * w1;
	matY += matrices[int( joint + 1 )] * w1;
	matZ += matrices[int( joint + 2 )] * w1;
	previousMatX += previousMatrices[int( joint + 0 )] * w1;
	previousMatY += previousMatrices[int( joint + 1 )] * w1;
	previousMatZ += previousMatrices[int( joint + 2 )] * w1;

	joint = int( vertex.color.z * 255.1 * 3.0 );
	matX += matrices[int( joint + 0 )] * w2;
	matY += matrices[int( joint + 1 )] * w2;
	matZ += matrices[int( joint + 2 )] * w2;
	previousMatX += previousMatrices[int( joint + 0 )] * w2;
	previousMatY += previousMatrices[int( joint + 1 )] * w2;
	previousMatZ += previousMatrices[int( joint + 2 )] * w2;

	joint = int( vertex.color.w * 255.1 * 3.0 );
	matX += matrices[int( joint + 0 )] * w3;
	matY += matrices[int( joint + 1 )] * w3;
	matZ += matrices[int( joint + 2 )] * w3;
	previousMatX += previousMatrices[int( joint + 0 )] * w3;
	previousMatY += previousMatrices[int( joint + 1 )] * w3;
	previousMatZ += previousMatrices[int( joint + 2 )] * w3;

	float4 modelPosition;
	modelPosition.x = dot4( matX, vertex.position );
	modelPosition.y = dot4( matY, vertex.position );
	modelPosition.z = dot4( matZ, vertex.position );
	modelPosition.w = 1.0;

	float4 previousModelPosition;
	previousModelPosition.x = dot4( previousMatX, vertex.position );
	previousModelPosition.y = dot4( previousMatY, vertex.position );
	previousModelPosition.z = dot4( previousMatZ, vertex.position );
	previousModelPosition.w = 1.0;
#else
	float4 modelPosition = vertex.position;
	float4 previousModelPosition = vertex.position;
#endif

	result.position.x = dot4( modelPosition, pc.rpMVPmatrixX );
	result.position.y = dot4( modelPosition, pc.rpMVPmatrixY );
	result.position.z = dot4( modelPosition, pc.rpMVPmatrixZ );
	result.position.w = dot4( modelPosition, pc.rpMVPmatrixW );

	result.previousClipPosition.x = dot4( previousModelPosition, pc.rpModelMatrixX );
	result.previousClipPosition.y = dot4( previousModelPosition, pc.rpModelMatrixY );
	result.previousClipPosition.z = dot4( previousModelPosition, pc.rpModelMatrixZ );
	result.previousClipPosition.w = dot4( previousModelPosition, pc.rpModelMatrixW );
}
