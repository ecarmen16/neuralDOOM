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
	result.position.x = dot4( vertex.position, pc.rpMVPmatrixX );
	result.position.y = dot4( vertex.position, pc.rpMVPmatrixY );
	result.position.z = dot4( vertex.position, pc.rpMVPmatrixZ );
	result.position.w = dot4( vertex.position, pc.rpMVPmatrixW );

	result.previousClipPosition.x = dot4( vertex.position, pc.rpModelMatrixX );
	result.previousClipPosition.y = dot4( vertex.position, pc.rpModelMatrixY );
	result.previousClipPosition.z = dot4( vertex.position, pc.rpModelMatrixZ );
	result.previousClipPosition.w = dot4( vertex.position, pc.rpModelMatrixW );
}
