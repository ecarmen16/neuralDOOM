// SPDX-License-Identifier: GPL-3.0-or-later
// Small GPU-only texture cache; retain UV detail without CPU texture readback.
cbuffer Parameters : register(b0) { float4 Options; }; // slice, decode, source mip, tile size
Texture2D<float4> Source : register(t0);
SamplerState LinearWrap : register(s0);
RWTexture2DArray<float4> Atlas : register(u0);
float3 Linear(float3 c)
{
    c = saturate(c);
    return float3(c.r <= 0.04045 ? c.r / 12.92 : pow((c.r + 0.055) / 1.055, 2.4),
        c.g <= 0.04045 ? c.g / 12.92 : pow((c.g + 0.055) / 1.055, 2.4),
        c.b <= 0.04045 ? c.b / 12.92 : pow((c.b + 0.055) / 1.055, 2.4));
}
[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= (uint)Options.w)) return;
    float4 value = Source.SampleLevel(LinearWrap, (float2(tid.xy) + 0.5) / Options.w, Options.z);
    if (Options.y == 1)
    {
        // Same YCoCg decode as the native material interaction shader.
        value.z = rcp(value.z * 31.875 + 1);
        value.xy *= value.z;
        value.rgb = float3(value.x - value.y + value.w,
            value.y - 0.50196078 * value.z + value.w,
            -value.x - value.y + 1.00392156 * value.z + value.w);
    }
    if (Options.y != 0) value.rgb = Linear(value.rgb);
    Atlas[uint3(tid.xy, (uint)Options.x)] = float4(value.rgb, 1);
}
