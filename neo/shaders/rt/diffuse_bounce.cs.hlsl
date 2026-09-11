// SPDX-License-Identifier: GPL-3.0-or-later
// One diffuse bounce with textured materials, emissives, authored light falloff
// and visibility rays. The complete static BSP is traced, including offscreen hits.
#include "ray_materials.hlsli"
RWTexture2D<float4> Bounce : register(u0);
RWStructuredBuffer<uint> Stats : register(u1);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= (uint2)Viewport.zw)) return;
    Bounce[tid.xy] = 0;
    uint2 local = tid.xy;
    uint2 pixel = local + (uint2)Viewport.xy;
    bool sampled = ((tid.x | tid.y) & 15) == 0;
    if (sampled) InterlockedAdd(Stats[0], 1);
    float depth = Depth[pixel];
    if (depth <= 0 || depth >= 0.999999) return;
    float2 uv = (float2(local) + 0.5) / Viewport.zw;
    float4 h = mul(ClipToWorld, float4(uv * float2(2, -2) + float2(-1, 1), depth, 1));
    if (abs(h.w) < 1e-8) return;
    float3 receiver = h.xyz / h.w;
    float distance = length(receiver - CameraRadius.xyz);
    if (!isfinite(distance) || distance < 0.01) return;
    RayDesc primary;
    primary.Origin = CameraRadius.xyz;
    primary.Direction = (receiver - primary.Origin) / distance;
    primary.TMin = 0.01;
    primary.TMax = distance + max(0.5, distance * 0.001);
    RayQuery<RAY_FLAG_NONE> surface;
    surface.TraceRayInline(Scene, RAY_FLAG_NONE, 255, primary);
    while (surface.Proceed())
    {
        if (surface.CandidateType() == CANDIDATE_NON_OPAQUE_TRIANGLE &&
            RaySurfaceVisible(surface.CandidateInstanceID() + surface.CandidatePrimitiveIndex()))
            surface.CommitNonOpaqueTriangleHit();
    }
    if (surface.CommittedStatus() != COMMITTED_TRIANGLE_HIT ||
        abs(surface.CommittedRayT() - distance) > max(0.5, distance * 0.001)) return;
    float3 normal, receiverAlbedo, ignoredEmission;
    if (!Surface(surface.CommittedInstanceID() + surface.CommittedPrimitiveIndex(), surface.CommittedTriangleBarycentrics(), primary.Direction, normal, receiverAlbedo, ignoredEmission)) return;
    if (sampled) InterlockedAdd(Stats[1], 1);
    float3 tangent = normalize(cross(abs(normal.z) < 0.9 ? float3(0, 0, 1) : float3(0, 1, 0), normal));
    float3 bitangent = cross(normal, tangent);
    float3 sum = 0;
    uint samples = (uint)Options.x;
    for (uint i = 0; i < samples; ++i)
    {
        float r = sqrt((i + 0.5) / samples);
        float phi = i * 2.39996323;
        RayDesc ray;
        ray.Origin = receiver + normal * 0.5;
        ray.Direction = tangent * (r * cos(phi)) + bitangent * (r * sin(phi)) + normal * sqrt(1 - r * r);
        ray.TMin = 0.01;
        ray.TMax = CameraRadius.w;
        RayQuery<RAY_FLAG_NONE> bounce;
        bounce.TraceRayInline(Scene, RAY_FLAG_NONE, 255, ray);
        while (bounce.Proceed())
        {
            if (bounce.CandidateType() == CANDIDATE_NON_OPAQUE_TRIANGLE &&
                RaySurfaceVisible(bounce.CandidateInstanceID() + bounce.CandidatePrimitiveIndex()))
                bounce.CommitNonOpaqueTriangleHit();
        }
        if (bounce.CommittedStatus() != COMMITTED_TRIANGLE_HIT) continue;
        if (sampled) InterlockedAdd(Stats[2], 1);
        float3 hitNormal, hitAlbedo, emission;
        if (!Surface(bounce.CommittedInstanceID() + bounce.CommittedPrimitiveIndex(), bounce.CommittedTriangleBarycentrics(), ray.Direction, hitNormal, hitAlbedo, emission)) continue;
        float3 hit = ray.Origin + ray.Direction * bounce.CommittedRayT();
        float3 radiance = hitAlbedo * Incident(hit, hitNormal) + emission * Options.z;
        float3 cached;
        float cacheWeight = CachedRadiance(hit, cached);
        // Normal lighting samples before generic emissives; late diagnostics
        // retain the completed-scene cache, which already includes one copy.
        float cachedEmissionScale = AtlasOptions.y == 0 ? Options.z : max(Options.z - 1, 0);
        radiance = lerp(radiance, cached + emission * cachedEmissionScale, cacheWeight);
        if (sampled && cacheWeight > 0) InterlockedAdd(Stats[6], 1);
        if (sampled && any(emission > 1e-4)) InterlockedAdd(Stats[7], 1);
        // Limit rare bright emissive fireflies while retaining HDR values above 1.
        radiance *= min(1.0, 8.0 / max(1e-5, max(max(radiance.r, radiance.g), radiance.b)));
        sum += radiance;
        if (sampled && max(max(radiance.r, radiance.g), radiance.b) - min(min(radiance.r, radiance.g), radiance.b) > 0.005) InterlockedAdd(Stats[3], 1);
    }
    float3 indirect = receiverAlbedo * sum * (Options.y / samples);
    if (any(!isfinite(indirect))) { InterlockedAdd(Stats[5], 1); return; }
    if (sampled && any(indirect > 1e-4)) InterlockedAdd(Stats[4], 1);
    Bounce[tid.xy] = float4(AtlasOptions.y == 4 ? receiverAlbedo : indirect, distance);
}
