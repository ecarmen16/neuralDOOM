// SPDX-License-Identifier: GPL-3.0-or-later
// Native intersection diagnostics; no lighting or temporal reconstruction.
struct RayInput
{
    float3 origin;
    float tMin;
    float3 direction;
    float tMax;
    uint mask;
    uint3 padding;
};

struct RayHit
{
    uint hit;
    float distance;
    uint instance;
    uint primitive;
};

RaytracingAccelerationStructure Scene : register(t0);
StructuredBuffer<RayInput> Rays : register(t1);
RWStructuredBuffer<RayHit> Hits : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 threadID : SV_DispatchThreadID)
{
    uint count, stride;
    Rays.GetDimensions(count, stride);
    if (threadID.x >= count) return;

    RayInput input = Rays[threadID.x];
    RayDesc ray;
    ray.Origin = input.origin;
    ray.Direction = input.direction;
    ray.TMin = input.tMin;
    ray.TMax = input.tMax;
    RayQuery<RAY_FLAG_FORCE_OPAQUE> query;
    query.TraceRayInline(Scene, RAY_FLAG_NONE, input.mask, ray);
    while (query.Proceed()) {}

    RayHit result;
    result.hit = query.CommittedStatus() == COMMITTED_TRIANGLE_HIT ? 1 : 0;
    result.distance = result.hit ? query.CommittedRayT() : -1.0;
    result.instance = result.hit ? query.CommittedInstanceID() : 0xffffffff;
    result.primitive = result.hit ? query.CommittedPrimitiveIndex() : 0xffffffff;
    Hits[threadID.x] = result;
}
