// SPDX-License-Identifier: GPL-3.0-or-later
#include "ray_materials.hlsli"
#include "reflection_parameters.hlsli"
Texture2D<float4> ProbeSpecular : register(t9);
Texture2D<float4> SpecularResponse : register(t10);
Texture2D<float4> ReflectionNormal : register(t11);
RWTexture2D<float4> Reflection : register(u0); // premultiplied incident radiance, hit coverage
RWStructuredBuffer<uint> Stats : register(u1);
RWTexture2D<float4> Guide : register(u2); // oct normal, camera distance, roughness

uint Hash(uint v)
{
    v ^= v >> 16; v *= 0x7feb352d; v ^= v >> 15; v *= 0x846ca68b; return v ^ (v >> 16);
}
float Random(inout uint seed)
{
    seed = Hash(seed);
    return (seed & 0x00ffffff) / 16777216.0;
}
[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= (uint2)Viewport.zw)) return;
    Reflection[tid.xy] = 0;
    Guide[tid.xy] = 0;
    uint2 pixel = tid.xy + (uint2)Viewport.xy;
    bool sampled = ((tid.x | tid.y) & 15) == 0;
    if (sampled) InterlockedAdd(Stats[0], 1);
    float4 response = SpecularResponse[pixel];
    float4 mappedNormal = ReflectionNormal[pixel];
    if (ProbeSpecular[pixel].a <= 0 || mappedNormal.a <= 0 ||
        any(!isfinite(response)) || any(!isfinite(mappedNormal)) ||
        response.a >= ReflectionOptions.z || max(max(response.r, response.g), response.b) < 1e-5) return;
    float roughness = clamp(response.a, 0.02, 1.0);
    float depth = Depth[pixel];
    if (depth <= 0 || depth >= 0.999999) return;
    float2 uv = (float2(tid.xy) + 0.5) / Viewport.zw;
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
    RayQuery<RAY_FLAG_FORCE_OPAQUE> surface;
    surface.TraceRayInline(Scene, RAY_FLAG_NONE, 255, primary);
    while (surface.Proceed()) {}
    if (surface.CommittedStatus() != COMMITTED_TRIANGLE_HIT ||
        abs(surface.CommittedRayT() - distance) > max(0.5, distance * 0.001)) return;
    float3 geometricNormal, unusedAlbedo, unusedEmission;
    if (!Surface(surface.CommittedPrimitiveIndex(), surface.CommittedTriangleBarycentrics(), primary.Direction,
        geometricNormal, unusedAlbedo, unusedEmission)) return;
    if (dot(mappedNormal.xyz, mappedNormal.xyz) < 1e-6) return;
    float3 normal = normalize(mappedNormal.xyz);
    float3 view = -primary.Direction;
    if (dot(normal, geometricNormal) <= 0 || dot(normal, view) <= 0) return;
    if (sampled) InterlockedAdd(Stats[1], 1);
    Guide[tid.xy] = float4(EncodeReflectionNormal(normal), min(distance, 65000.0), roughness);
    float3 tangent = normalize(cross(abs(normal.z) < 0.9 ? float3(0, 0, 1) : float3(0, 1, 0), normal));
    float3 bitangent = cross(normal, tangent);
    uint seed = Hash(tid.x + tid.y * (uint)Viewport.z + (uint)HistoryOptions.y * 747796405u);
    float alpha = roughness * roughness;
    float3 sum = 0;
    float totalWeight = 0, hitWeight = 0;
    // A GGX-prefiltered radiance estimate using the native split-sum BRDF
    // response. This is a hybrid reflection, not an unbiased path tracer.
    for (uint i = 0; i < (uint)ReflectionOptions.x; ++i)
    {
        float u = (i + Random(seed)) / ReflectionOptions.x;
        float phi = Random(seed) * 6.283185307;
        float cosTheta = sqrt((1 - u) / max(1e-6, 1 + (alpha * alpha - 1) * u));
        float sinTheta = sqrt(saturate(1 - cosTheta * cosTheta));
        float3 halfVector = tangent * (sinTheta * cos(phi)) + bitangent * (sinTheta * sin(phi)) + normal * cosTheta;
        float3 direction = reflect(-view, halfVector);
        float weight = saturate(dot(normal, direction));
        if (weight <= 0) continue;
        totalWeight += weight;
        if (dot(geometricNormal, direction) <= 0) continue;
        RayDesc ray;
        ray.Origin = receiver + geometricNormal * 0.5;
        ray.Direction = direction;
        ray.TMin = 0.01;
        ray.TMax = ReflectionOptions.w;
        RayQuery<RAY_FLAG_FORCE_OPAQUE> reflected;
        reflected.TraceRayInline(Scene, RAY_FLAG_NONE, 255, ray);
        while (reflected.Proceed()) {}
        if (sampled) InterlockedAdd(Stats[2], 1);
        if (reflected.CommittedStatus() != COMMITTED_TRIANGLE_HIT) continue;
        float3 hitNormal, hitAlbedo, emission;
        if (!Surface(reflected.CommittedPrimitiveIndex(), reflected.CommittedTriangleBarycentrics(), direction, hitNormal, hitAlbedo, emission)) continue;
        float3 hit = ray.Origin + direction * reflected.CommittedRayT();
        float3 cached;
        float cacheWeight = CachedRadiance(hit, cached);
        float3 radiance = cached;
        // Skip the authored-light loop when the complete native shading is available.
        if (cacheWeight < 0.999) radiance = lerp(hitAlbedo * Incident(hit, hitNormal) + emission, cached, cacheWeight);
        if (any(!isfinite(radiance))) { InterlockedAdd(Stats[5], 1); continue; }
        radiance = max(radiance, 0);
        radiance *= min(1.0, 16.0 / max(1e-5, max(max(radiance.r, radiance.g), radiance.b)));
        sum += radiance * weight;
        hitWeight += weight;
        if (sampled)
        {
            InterlockedAdd(Stats[3], 1);
            if (cacheWeight > 0) InterlockedAdd(Stats[6], 1);
            if (any(emission > 1e-4)) InterlockedAdd(Stats[7], 1);
        }
    }
    float fade = saturate((ReflectionOptions.z - roughness) / 0.15);
    float coverage = saturate(hitWeight / max(totalWeight, 1e-6)) * fade;
    // Apply the current material response after filtering to avoid borrowing
    // another surface's reflectivity or old Fresnel response.
    float3 contribution = sum / max(totalWeight, 1e-6) * fade;
    if (any(!isfinite(contribution))) { InterlockedAdd(Stats[5], 1); return; }
    Reflection[tid.xy] = float4(contribution, coverage);
    if (sampled && coverage > 0) InterlockedAdd(Stats[4], 1);
}
