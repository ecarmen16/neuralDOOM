// SPDX-License-Identifier: GPL-3.0-or-later
cbuffer Parameters : register(b0)
{
    row_major float4x4 ClipToWorld;
    row_major float4x4 WorldToClip;
    float4 CameraRadius;
    float4 Viewport;
    float4 Options;
    float4 AtlasOptions;
};
Texture2D<float4> Bounce : register(t0);
Texture2D<float> Depth : register(t1);
RWTexture2D<float4> SceneColor : register(u0);
[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= (uint2)Viewport.zw)) return;
    uint2 pixel = tid.xy + (uint2)Viewport.xy;
    float4 color = SceneColor[pixel];
    float depth = Depth[pixel];
    float3 indirect = 0;
    // A rejected primary receiver (weapon, character or moving door) must not
    // borrow neighboring static-surface lighting during spatial filtering.
    if (depth > 0 && depth < 0.999999 && Bounce[tid.xy].a > 0)
    {
        float2 uv = (float2(tid.xy) + 0.5) / Viewport.zw;
        float4 h = mul(ClipToWorld, float4(uv * float2(2, -2) + float2(-1, 1), depth, 1));
        if (abs(h.w) > 1e-8)
        {
            float distance = length(h.xyz / h.w - CameraRadius.xyz);
            float weight = 0;
            int2 center = int2(tid.xy);
            int2 size = int2(Viewport.zw);
            // Full-resolution spatial filtering; do not smear through silhouettes.
            for (int y = -1; y <= 1; ++y)
            for (int x = -1; x <= 1; ++x)
            {
                int2 p = clamp(center + int2(x, y), 0, size - 1);
                float4 sampleValue = Bounce[p];
                if (sampleValue.a <= 0) continue;
                float w = exp2(-abs(sampleValue.a - distance) / max(0.5, distance * 0.002));
                w *= rcp(1.0 + x * x + y * y);
                indirect += sampleValue.rgb * w;
                weight += w;
            }
            indirect /= max(weight, 1e-5);
        }
    }
    SceneColor[pixel] = float4(AtlasOptions.y >= 3 ? indirect : color.rgb + indirect, color.a);
}
