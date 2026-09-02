/*
===========================================================================

Doom 3 BFG Edition GPL Source Code

This file is part of the Doom 3 BFG Edition Source Code and is distributed
under the GNU General Public License version 3 and the additional terms that
apply to this source tree.

===========================================================================
*/

#include "global_inc.hlsl"
#include "renderParmSet4.inc.hlsl"

// Texture-aware silhouette vertex shader for temporal masks.
// *INDENT-OFF*
#if USE_GPU_SKINNING
StructuredBuffer<float4> matrices : register(t11);
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
	float2 texcoord0 : TEXCOORD0_centroid;
};
// *INDENT-ON*

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

	joint = int( vertex.color.y * 255.1 * 3.0 );
	matX += matrices[int( joint + 0 )] * w1;
	matY += matrices[int( joint + 1 )] * w1;
	matZ += matrices[int( joint + 2 )] * w1;
	joint = int( vertex.color.z * 255.1 * 3.0 );
	matX += matrices[int( joint + 0 )] * w2;
	matY += matrices[int( joint + 1 )] * w2;
	matZ += matrices[int( joint + 2 )] * w2;
	joint = int( vertex.color.w * 255.1 * 3.0 );
	matX += matrices[int( joint + 0 )] * w3;
	matY += matrices[int( joint + 1 )] * w3;
	matZ += matrices[int( joint + 2 )] * w3;

	float4 modelPosition;
	modelPosition.x = dot4( matX, vertex.position );
	modelPosition.y = dot4( matY, vertex.position );
	modelPosition.z = dot4( matZ, vertex.position );
	modelPosition.w = 1.0;
#else
	float4 modelPosition = vertex.position;
#endif

	result.position.x = dot4( modelPosition, pc.rpMVPmatrixX );
	result.position.y = dot4( modelPosition, pc.rpMVPmatrixY );
	result.position.z = dot4( modelPosition, pc.rpMVPmatrixZ );
	result.position.w = dot4( modelPosition, pc.rpMVPmatrixW );
	result.position.xyz = psxVertexJitter( pc.rpPSXDistortions, pc.rpProjectionMatrixW, result.position );

	if( pc.rpTexGen0Enabled.x > 0.0 )
	{
		result.texcoord0.x = dot4( modelPosition, pc.rpTexGen0S );
		result.texcoord0.y = dot4( modelPosition, pc.rpTexGen0T );
	}
	else
	{
		result.texcoord0.x = dot4( vertex.texcoord.xy, pc.rpTextureMatrixS );
		result.texcoord0.y = dot4( vertex.texcoord.xy, pc.rpTextureMatrixT );
	}
}
