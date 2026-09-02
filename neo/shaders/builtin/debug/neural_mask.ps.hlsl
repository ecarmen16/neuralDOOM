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

// rpColor.x selects RGB intensity instead of alpha coverage.
// rpColor.y scales the contribution before max blending into the R8 target.
// *INDENT-OFF*
Texture2D t_BaseColor : register( t0 VK_DESCRIPTOR_SET( 1 ) );
SamplerState s_Sampler : register( s0 VK_DESCRIPTOR_SET( 2 ) );

struct PS_IN
{
	float4 position : SV_POSITION;
	float2 texcoord0 : TEXCOORD0_centroid;
};

struct PS_OUT
{
	float mask : SV_Target0;
};
// *INDENT-ON*

void main( in PS_IN fragment, out PS_OUT result )
{
	float4 sampleColor = t_BaseColor.Sample( s_Sampler, fragment.texcoord0 );
	float rgbCoverage = max( sampleColor.r, max( sampleColor.g, sampleColor.b ) );
	float coverage = lerp( sampleColor.a, rgbCoverage, pc.rpColor.x );
	result.mask = saturate( coverage * pc.rpColor.y );
}
