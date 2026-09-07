// SPDX-License-Identifier: GPL-3.0-or-later
cbuffer ReflectionParameters : register(b1)
{
    row_major float4x4 PreviousWorldToClip;
    float4 PreviousCamera;
    float4 ReflectionOptions; // samples, strength, roughness limit, ray distance
    float4 HistoryOptions; // history valid, frame seed, debug view, unused
};
float2 EncodeReflectionNormal(float3 n)
{
    n /= max(abs(n.x) + abs(n.y) + abs(n.z), 1e-6);
    return n.z >= 0 ? n.xy : (1 - abs(n.yx)) * float2(n.x >= 0 ? 1 : -1, n.y >= 0 ? 1 : -1);
}
float3 DecodeReflectionNormal(float2 p)
{
    float3 n = float3(p, 1 - abs(p.x) - abs(p.y));
    float t = saturate(-n.z);
    n.xy += float2(n.x >= 0 ? -t : t, n.y >= 0 ? -t : t);
    return normalize(n);
}
