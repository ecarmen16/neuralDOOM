// SPDX-License-Identifier: GPL-3.0-or-later
// Static-world AO. Existing SSAO remains on receivers absent from the ray scene.
cbuffer Parameters : register(b0)
{
    row_major float4x4 ClipToWorld;
    float4 CameraRadius;
    float4 Viewport;
    float4 Options; // strength, hemisphere sample count
};
RaytracingAccelerationStructure Scene : register(t0);
Texture2D<float> Depth : register(t1);
StructuredBuffer<float3> Positions : register(t2);
StructuredBuffer<uint> Indices : register(t3);
RWTexture2D<float> Occlusion : register(u0);
RWStructuredBuffer<uint> Stats : register(u1);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= (uint2)Viewport.zw)) return;
    uint2 pixel = tid.xy + (uint2)Viewport.xy;
    bool sampleStats = ((tid.x | tid.y) & 31) == 0;
    if (sampleStats) InterlockedAdd(Stats[0], 1);
    float depth = Depth[pixel];
    if (depth >= 0.999999 || depth <= 0) return;
    float2 uv = (float2(tid.xy) + 0.5) / Viewport.zw;
    float4 h = mul(ClipToWorld, float4(uv * float2(2, -2) + float2(-1, 1), depth, 1));
    if (abs(h.w) < 1e-8) return;
    float3 receiver = h.xyz / h.w;
    float3 toReceiver = receiver - CameraRadius.xyz;
    float distance = length(toReceiver);
    if (!isfinite(distance) || distance < 0.01) return;
    RayDesc primary;
    primary.Origin = CameraRadius.xyz;
    primary.Direction = toReceiver / distance;
    primary.TMin = 0.01;
    primary.TMax = distance + max(0.5, distance * 0.001);
    RayQuery<RAY_FLAG_FORCE_OPAQUE> surface;
    surface.TraceRayInline(Scene, RAY_FLAG_NONE, 255, primary);
    while (surface.Proceed()) {}
    if (surface.CommittedStatus() != COMMITTED_TRIANGLE_HIT) return;
    // Reject weapon depth hacks, animated/rigid receivers and omitted cutouts.
    if (abs(surface.CommittedRayT() - distance) > max(0.5, distance * 0.001)) return;
    uint triangleIndex = (surface.CommittedInstanceID() + surface.CommittedPrimitiveIndex()) * 3;
    float3 a = Positions[Indices[triangleIndex]];
    float3 b = Positions[Indices[triangleIndex + 1]];
    float3 c = Positions[Indices[triangleIndex + 2]];
    float3 normal = cross(b - a, c - a);
    if (dot(normal, normal) < 1e-12) return;
    normal = normalize(normal);
    if (dot(normal, primary.Direction) > 0) normal = -normal;
    float3 tangent = normalize(cross(abs(normal.z) < 0.9 ? float3(0, 0, 1) : float3(0, 1, 0), normal));
    float3 bitangent = cross(normal, tangent);
    float3 hitPosition = primary.Origin + primary.Direction * surface.CommittedRayT();
    float blocked = 0;
    // Fixed cosine-weighted directions avoid frame-varying noise/history needs.
    uint sampleCount = (uint)Options.y;
    for (uint i = 0; i < sampleCount; ++i)
    {
        float r = sqrt((i + 0.5) / sampleCount);
        float phi = i * 2.39996323;
        RayDesc ray;
        ray.Origin = hitPosition + normal * 0.5;
        ray.Direction = tangent * (r * cos(phi)) + bitangent * (r * sin(phi)) + normal * sqrt(1 - r * r);
        ray.TMin = 0.01;
        ray.TMax = CameraRadius.w;
        RayQuery<RAY_FLAG_FORCE_OPAQUE> query;
        query.TraceRayInline(Scene, RAY_FLAG_NONE, 255, ray);
        while (query.Proceed()) {}
        if (query.CommittedStatus() == COMMITTED_TRIANGLE_HIT)
            blocked += 1.0 - saturate(query.CommittedRayT() / CameraRadius.w);
    }
    Occlusion[pixel] = saturate(1.0 - Options.x * blocked / sampleCount);
    if (sampleStats)
    {
        InterlockedAdd(Stats[1], 1);
        if (blocked > 0) InterlockedAdd(Stats[2], 1);
    }
}
