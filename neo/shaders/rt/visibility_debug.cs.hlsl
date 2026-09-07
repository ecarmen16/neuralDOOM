// SPDX-License-Identifier: GPL-3.0-or-later
cbuffer Parameters : register(b0) { float4 Viewport; };
Texture2D<float> Visibility : register(t0);
RWTexture2D<float4> SceneColor : register(u0);
[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= (uint2)Viewport.zw)) return;
    uint2 pixel = tid.xy + (uint2)Viewport.xy;
    float value = saturate(Visibility[pixel]);
    SceneColor[pixel] = float4(value, value, value, 1);
}
