/*
===========================================================================

Doom 3 BFG Edition GPL Source Code

This file is part of the Doom 3 BFG Edition Source Code and is distributed
under the GNU General Public License version 3 and the additional terms that
apply to this source tree.

===========================================================================
*/

Texture2D maskTexture : register( t0 );
SamplerState maskSampler : register( s0 );

struct PS_IN
{
	float4 position : SV_Position;
	float2 uv : UV;
};

void main( PS_IN fragment, out float4 result : SV_Target )
{
	float mask = maskTexture.Sample( maskSampler, fragment.uv ).r;
#if TRANSPARENCY_MASK
	result = float4( 0.0, mask, mask, 1.0 );
#else
	result = float4( mask, 0.0, 0.0, 1.0 );
#endif
}
