// SPDX-License-Identifier: GPL-3.0-or-later
cbuffer Parameters : register(b0)
{
    row_major float4x4 ClipToWorld;
    row_major float4x4 WorldToClip;
    float4 CameraRadius, Viewport, Options, AtlasOptions;
};
#include "reflection_parameters.hlsli"
Texture2D<float4> Reflection : register(t0);
Texture2D<float4> ProbeSpecular : register(t1);
Texture2D<float4> Guide : register(t2);
Texture2D<float4> SpecularResponse : register(t3);
RWTexture2D<float4> SceneColor : register(u0);
[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= (uint2)Viewport.zw)) return;
    uint2 pixel = tid.xy + (uint2)Viewport.xy;
    float4 reflection = Reflection[tid.xy], guide = Guide[tid.xy];
    float3 response = SpecularResponse[pixel].rgb;
    if (guide.z <= 0 || reflection.a <= 0 || any(!isfinite(response))) reflection = 0;
    else reflection.rgb *= max(response, 0);
    float4 scene = SceneColor[pixel];
    if (HistoryOptions.z == 5) { SceneColor[pixel] = float4(min(reflection.rgb, 65504.0), scene.a); return; }
    if (HistoryOptions.z == 6) { SceneColor[pixel] = float4(guide.z > 0 ? guide.www : 0, scene.a); return; }
    // Keep other diagnostic views independent of reflection compositing.
    if (HistoryOptions.z != 0 || ReflectionOptions.y <= 0 || guide.z <= 0 || reflection.a <= 0) return;
    float3 delta = reflection.rgb - ProbeSpecular[pixel].rgb * saturate(reflection.a);
    if (any(!isfinite(delta))) return;
    SceneColor[pixel] = float4(clamp(scene.rgb + ReflectionOptions.y * delta, 0, 65504.0), scene.a);
}
