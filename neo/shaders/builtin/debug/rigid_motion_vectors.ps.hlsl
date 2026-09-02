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

struct PS_IN
{
	float4 position : SV_Position;
	float4 previousClipPosition : TEXCOORD0;
};

void main( PS_IN fragment, out float4 result : SV_Target )
{
	if( fragment.previousClipPosition.w <= 0.0 )
	{
		discard;
	}

	float2 previousTexCoord;
	previousTexCoord.x = 0.5 + ( fragment.previousClipPosition.x / fragment.previousClipPosition.w ) * 0.5;
	previousTexCoord.y = 0.5 - ( fragment.previousClipPosition.y / fragment.previousClipPosition.w ) * 0.5;

	float2 previousWindowPosition = previousTexCoord * pc.rpScreenCorrectionFactor.xy;
	float2 motion = previousWindowPosition - fragment.position.xy;
	result = float4( motion, 0.0, 1.0 );
}
