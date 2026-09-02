/*
===========================================================================

Doom 3 BFG Edition GPL Source Code

This file is part of the Doom 3 BFG Edition Source Code and is distributed
under the GNU General Public License version 3 and the additional terms that
apply to this source tree.

===========================================================================
*/

Texture2D<float2> motionVectors : register( t0 );
SamplerState linearSampler : register( s0 );

struct PS_IN
{
	float4 posClip : SV_Position;
	float2 uv : UV;
};

void main( PS_IN fragment, out float4 result : SV_Target )
{
	// The source is current-pixel to previous-pixel displacement in pixels.
	// Map the signed -8..8 pixel range around neutral gray for visual inspection.
	float2 motion = clamp( motionVectors.Sample( linearSampler, fragment.uv ), -8.0, 8.0 );
	float2 encodedMotion = motion * ( 0.5 / 8.0 ) + 0.5;

	result = float4( encodedMotion, 0.5, 1.0 );
}
