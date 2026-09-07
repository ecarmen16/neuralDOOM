// SPDX-License-Identifier: GPL-3.0-or-later
cbuffer Parameters : register(b0)
{
    row_major float4x4 ClipToWorld;
    row_major float4x4 WorldToClip;
    float4 CameraRadius, Viewport, Options, AtlasOptions;
};
#include "reflection_parameters.hlsli"
Texture2D<float4> Raw : register(t0);
Texture2D<float4> Guide : register(t1);
Texture2D<float4> Previous : register(t2);
Texture2D<float4> PreviousGuide : register(t3);
Texture2D<float> Depth : register(t4);
RWTexture2D<float4> Filtered : register(u0);
[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= (uint2)Viewport.zw)) return;
    int2 p = int2(tid.xy), size = int2(Viewport.zw);
    float4 center = Raw[p], guide = Guide[p];
    Filtered[p] = center;
    // Rejected receivers and current misses never inherit another surface's reflection.
    if (guide.z <= 0 || center.a <= 0) return;
    float3 normal = DecodeReflectionNormal(guide.xy);
    float4 sum = 0, low = center, high = center;
    float weights = 0;
    int radius = guide.w > 0.12 ? 1 : 0;
    for (int y = -radius; y <= radius; ++y)
    for (int x = -radius; x <= radius; ++x)
    {
        int2 q = clamp(p + int2(x, y), 0, size - 1);
        float4 sampleGuide = Guide[q], value = Raw[q];
        if (sampleGuide.z <= 0 || value.a <= 0) continue;
        float similarity = dot(normal, DecodeReflectionNormal(sampleGuide.xy));
        if (similarity < 0.9 || abs(sampleGuide.w - guide.w) > 0.08) continue;
        float w = exp2(-abs(sampleGuide.z - guide.z) / max(0.5, guide.z * 0.002));
        w *= pow(saturate(similarity), 32) / (1.0 + x * x + y * y);
        sum += value * w; weights += w;
        if (w > 0.1) { low = min(low, value); high = max(high, value); }
    }
    float4 filtered = sum / max(weights, 1e-6);
    if (HistoryOptions.x > 0)
    {
        uint2 pixel = tid.xy + (uint2)Viewport.xy;
        float2 uv = (float2(tid.xy) + 0.5) / Viewport.zw;
        float4 h = mul(ClipToWorld, float4(uv * float2(2, -2) + float2(-1, 1), Depth[pixel], 1));
        if (abs(h.w) > 1e-8)
        {
            float3 world = h.xyz / h.w;
            float4 oldClip = mul(PreviousWorldToClip, float4(world, 1));
            float2 oldUV = oldClip.xy / max(oldClip.w, 1e-6) * float2(0.5, -0.5) + 0.5;
            if (oldClip.w > 0 && all(oldUV > 0) && all(oldUV < 1))
            {
                int2 q = min(int2(oldUV * Viewport.zw), size - 1);
                float4 oldGuide = PreviousGuide[q], history = Previous[q];
                float expectedDistance = length(world - PreviousCamera.xyz);
                if (oldGuide.z > 0 && abs(oldGuide.z - expectedDistance) < max(1.0, expectedDistance * 0.003) &&
                    abs(oldGuide.w - guide.w) < 0.04 && dot(normal, DecodeReflectionNormal(oldGuide.xy)) > 0.95 &&
                    history.a > 0 && all(isfinite(history)))
                {
                    // Clamp reprojected lighting to the current neighborhood to
                    // limit trails from animated emissives and view-dependent hits.
                    history = clamp(history, low, high);
                    filtered = lerp(filtered, history, guide.w > 0.12 ? 0.8 : 0.25);
                }
            }
        }
    }
    Filtered[p] = filtered;
}
