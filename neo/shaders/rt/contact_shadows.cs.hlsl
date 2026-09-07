// SPDX-License-Identifier: GPL-3.0-or-later
// Attenuate only this light's raster contribution, retaining all previous light.
cbuffer Parameters : register(b0)
{
    row_major float4x4 ClipToWorld;
    float4 CameraRadius;
    float4 Viewport;
    float4 LightStrength;
    float4 Rectangle;
};
RaytracingAccelerationStructure Scene : register(t0);
Texture2D<float> Depth : register(t1);
StructuredBuffer<float3> Positions : register(t2);
StructuredBuffer<uint> Indices : register(t3);
Texture2D<float4> BeforeLight : register(t4);
RWTexture2D<float4> SceneColor : register(u0);
RWTexture2D<float> Visibility : register(u1);
RWStructuredBuffer<uint> Stats : register(u2);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= (uint2)Rectangle.zw)) return;
    uint2 pixel = tid.xy + (uint2)Rectangle.xy;
    bool sampled = ((pixel.x | pixel.y) & 31) == 0;
    if (sampled) InterlockedAdd(Stats[0], 1);
    float4 before = BeforeLight[pixel];
    float4 after = SceneColor[pixel];
    if (any(!isfinite(before)) || any(!isfinite(after)))
    {
        InterlockedAdd(Stats[4], 1);
        return;
    }
    // Pixels outside this light's actual raster influence need no rays.
    if (max(max(after.r - before.r, after.g - before.g), after.b - before.b) < 1e-5) return;
    float depth = Depth[pixel];
    if (depth >= 0.999999 || depth <= 0) return;
    float2 uv = (float2(pixel) + 0.5 - Viewport.xy) / Viewport.zw;
    float4 h = mul(ClipToWorld, float4(uv * float2(2, -2) + float2(-1, 1), depth, 1));
    if (abs(h.w) < 1e-8) return;
    float3 toReceiver = h.xyz / h.w - CameraRadius.xyz;
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
    if (surface.CommittedStatus() != COMMITTED_TRIANGLE_HIT ||
        abs(surface.CommittedRayT() - distance) > max(0.5, distance * 0.001)) return;
    uint index = surface.CommittedPrimitiveIndex() * 3;
    float3 a = Positions[Indices[index]];
    float3 b = Positions[Indices[index + 1]];
    float3 c = Positions[Indices[index + 2]];
    float3 normal = cross(b - a, c - a);
    if (dot(normal, normal) < 1e-12) return;
    normal = normalize(normal);
    if (dot(normal, primary.Direction) > 0) normal = -normal;
    RayDesc ray;
    ray.Origin = primary.Origin + primary.Direction * surface.CommittedRayT() + normal * 0.5;
    float3 toLight = LightStrength.xyz - ray.Origin;
    float lightDistance = length(toLight);
    if (!isfinite(lightDistance) || lightDistance <= 0.51) return;
    ray.Direction = toLight / lightDistance;
    if (dot(normal, ray.Direction) <= 0) return;
    ray.TMin = 0.01;
    ray.TMax = min(CameraRadius.w, lightDistance - 0.5);
    if (sampled) InterlockedAdd(Stats[1], 1);
    RayQuery<RAY_FLAG_FORCE_OPAQUE> contact;
    contact.TraceRayInline(Scene, RAY_FLAG_NONE, 255, ray);
    while (contact.Proceed()) {}
    if (contact.CommittedStatus() != COMMITTED_TRIANGLE_HIT) return;
    if (sampled) InterlockedAdd(Stats[2], 1);
    float visibility = 1.0 - LightStrength.w * saturate(1.0 - contact.CommittedRayT() / CameraRadius.w);
    float3 shaded = lerp(before.rgb, after.rgb, visibility);
    SceneColor[pixel] = float4(shaded, after.a);
    Visibility[pixel] = min(Visibility[pixel], visibility);
    if (sampled && any(abs(after.rgb - shaded) > 1e-5)) InterlockedAdd(Stats[3], 1);
}
