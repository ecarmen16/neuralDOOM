// SPDX-License-Identifier: GPL-3.0-or-later
// One diffuse bounce with textured materials, emissives, authored light falloff
// and visibility rays. The complete static BSP is traced, including offscreen hits.
cbuffer Parameters : register(b0)
{
    row_major float4x4 ClipToWorld;
    row_major float4x4 WorldToClip;
    float4 CameraRadius;
    float4 Viewport;
    float4 Options; // samples, intensity, emissive intensity, light count
    float4 AtlasOptions; // first light slice, debug mode, unused, unused
};
struct Material { float4 diffuse, emissive, diffuseS, diffuseT, emissiveS, emissiveT; };
struct Light { float4 originShadow, color, projectS, projectT, projectQ, falloff; };
RaytracingAccelerationStructure Scene : register(t0);
Texture2D<float> Depth : register(t1);
StructuredBuffer<float3> Positions : register(t2);
StructuredBuffer<uint> Indices : register(t3);
StructuredBuffer<float4> UVMaterials : register(t4);
StructuredBuffer<Material> Materials : register(t5);
StructuredBuffer<Light> Lights : register(t6);
Texture2DArray<float4> Atlas : register(t7);
Texture2D<float4> SurfaceRadiance : register(t8);
SamplerState LinearWrap : register(s0);
SamplerState LinearClamp : register(s1);
RWTexture2D<float4> Bounce : register(u0);
RWStructuredBuffer<uint> Stats : register(u1);

float3 Linear(float3 c)
{
    c = saturate(c);
    return float3(c.r <= 0.04045 ? c.r / 12.92 : pow((c.r + 0.055) / 1.055, 2.4),
        c.g <= 0.04045 ? c.g / 12.92 : pow((c.g + 0.055) / 1.055, 2.4),
        c.b <= 0.04045 ? c.b / 12.92 : pow((c.b + 0.055) / 1.055, 2.4));
}
bool Surface(uint primitive, float2 bary, float3 direction, out float3 normal, out float3 albedo, out float3 emission)
{
    uint3 idx = uint3(Indices[primitive * 3], Indices[primitive * 3 + 1], Indices[primitive * 3 + 2]);
    normal = cross(Positions[idx.y] - Positions[idx.x], Positions[idx.z] - Positions[idx.x]);
    albedo = emission = 0;
    if (dot(normal, normal) < 1e-12) return false;
    normal = normalize(normal);
    if (dot(normal, direction) > 0) normal = -normal;
    float4 a = UVMaterials[idx.x], b = UVMaterials[idx.y], c = UVMaterials[idx.z];
    float2 uv = a.xy * (1 - bary.x - bary.y) + b.xy * bary.x + c.xy * bary.y;
    Material m = Materials[(uint)a.z];
    float4 st = float4(uv, 0, 1);
    albedo = saturate(Atlas.SampleLevel(LinearWrap, float3(dot(st, m.diffuseS), dot(st, m.diffuseT), m.diffuse.w), 0).rgb * m.diffuse.rgb);
    emission = max(0, Atlas.SampleLevel(LinearWrap, float3(dot(st, m.emissiveS), dot(st, m.emissiveT), m.emissive.w), 0).rgb * m.emissive.rgb);
    return all(isfinite(albedo)) && all(isfinite(emission));
}
// Native raster shading is a radiance cache for visible hits. Geometric depth
// agreement rejects occluded hits; offscreen hits retain explicit material/light
// evaluation. This is a hybrid one-bounce estimate, not a full path tracer.
float CachedRadiance(float3 hit, out float3 radiance)
{
    radiance = 0;
    float4 clip = mul(WorldToClip, float4(hit, 1));
    if (clip.w <= 1e-6) return 0;
    float2 uv = clip.xy / clip.w * float2(0.5, -0.5) + 0.5;
    if (any(uv <= 0) || any(uv >= 1)) return 0;
    uint2 pixel = min((uint2)(uv * Viewport.zw), (uint2)Viewport.zw - 1) + (uint2)Viewport.xy;
    float depth = Depth[pixel];
    if (depth <= 0 || depth >= 0.999999) return 0;
    float2 centerUV = (float2(pixel) + 0.5 - Viewport.xy) / Viewport.zw;
    float4 h = mul(ClipToWorld, float4(centerUV * float2(2, -2) + float2(-1, 1), depth, 1));
    if (abs(h.w) < 1e-8) return 0;
    float distance = length(hit - CameraRadius.xyz);
    if (length(h.xyz / h.w - hit) > max(1.0, distance * 0.003)) return 0;
    radiance = max(SurfaceRadiance[pixel].rgb, 0);
    if (any(!isfinite(radiance))) { radiance = 0; return 0; }
    return saturate(min(min(uv.x, 1 - uv.x), min(uv.y, 1 - uv.y)) * 20);
}
float3 Incident(float3 position, float3 normal)
{
    float3 sum = 0;
    float4 p = float4(position, 1);
    for (uint i = 0; i < (uint)Options.w; ++i)
    {
        Light light = Lights[i];
        float q = dot(p, light.projectQ);
        if (q <= 1e-6) continue;
        float2 st = float2(dot(p, light.projectS), dot(p, light.projectT)) / q;
        float falloff = dot(p, light.falloff);
        if (any(st <= 0) || any(st >= 1) || falloff <= 0 || falloff >= 1) continue;
        float3 toLight = light.originShadow.xyz - position;
        float distance = length(toLight);
        if (distance <= 0.51) continue;
        float3 direction = toLight / distance;
        float cosine = saturate(dot(normal, direction));
        if (cosine <= 0) continue;
        float slice = AtlasOptions.x + i * 2;
        float3 projected = Atlas.SampleLevel(LinearClamp, float3(st, slice), 0).rgb;
        float3 fall = Atlas.SampleLevel(LinearClamp, float3(falloff, 0.5, slice + 1), 0).rgb;
        float3 radiance = Linear(projected * fall) * max(light.color.rgb, 0) * cosine;
        if (max(max(radiance.r, radiance.g), radiance.b) < 1e-5) continue;
        if (light.originShadow.w > 0)
        {
            RayDesc ray;
            ray.Origin = position + normal * 0.5;
            toLight = light.originShadow.xyz - ray.Origin;
            ray.Direction = normalize(toLight);
            ray.TMin = 0.01;
            ray.TMax = max(0.02, length(toLight) - 0.5);
            RayQuery<RAY_FLAG_FORCE_NON_OPAQUE | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> shadow;
            shadow.TraceRayInline(Scene, RAY_FLAG_NONE, 255, ray);
            while (shadow.Proceed())
            {
                if (shadow.CandidateType() == CANDIDATE_NON_OPAQUE_TRIANGLE)
                {
                    uint vertex = Indices[shadow.CandidatePrimitiveIndex() * 3];
                    if (Materials[(uint)UVMaterials[vertex].z].diffuseS.z > 0) shadow.CommitNonOpaqueTriangleHit();
                }
            }
            if (shadow.CommittedStatus() == COMMITTED_TRIANGLE_HIT) continue;
        }
        sum += radiance;
    }
    return sum;
}
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
    RayQuery<RAY_FLAG_FORCE_OPAQUE> surface;
    surface.TraceRayInline(Scene, RAY_FLAG_NONE, 255, primary);
    while (surface.Proceed()) {}
    if (surface.CommittedStatus() != COMMITTED_TRIANGLE_HIT ||
        abs(surface.CommittedRayT() - distance) > max(0.5, distance * 0.001)) return;
    float3 normal, receiverAlbedo, ignoredEmission;
    if (!Surface(surface.CommittedPrimitiveIndex(), surface.CommittedTriangleBarycentrics(), primary.Direction, normal, receiverAlbedo, ignoredEmission)) return;
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
        RayQuery<RAY_FLAG_FORCE_OPAQUE> bounce;
        bounce.TraceRayInline(Scene, RAY_FLAG_NONE, 255, ray);
        while (bounce.Proceed()) {}
        if (bounce.CommittedStatus() != COMMITTED_TRIANGLE_HIT) continue;
        if (sampled) InterlockedAdd(Stats[2], 1);
        float3 hitNormal, hitAlbedo, emission;
        if (!Surface(bounce.CommittedPrimitiveIndex(), bounce.CommittedTriangleBarycentrics(), ray.Direction, hitNormal, hitAlbedo, emission)) continue;
        float3 hit = ray.Origin + ray.Direction * bounce.CommittedRayT();
        float3 radiance = hitAlbedo * Incident(hit, hitNormal) + emission * Options.z;
        float3 cached;
        float cacheWeight = CachedRadiance(hit, cached);
        radiance = lerp(radiance, cached + emission * max(Options.z - 1, 0), cacheWeight);
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
