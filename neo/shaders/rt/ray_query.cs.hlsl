// SPDX-License-Identifier: GPL-3.0-or-later
#include "ray_visibility.hlsli"
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
    RayQuery<RAY_FLAG_NONE> query;
    query.TraceRayInline(Scene, RAY_FLAG_NONE, input.mask, ray);
    while (query.Proceed())
    {
        if (query.CandidateType() == CANDIDATE_NON_OPAQUE_TRIANGLE)
        {
            uint primitive = query.CandidateInstanceID() + query.CandidatePrimitiveIndex();
            // 0 = ordinary diagnostic, 1 = camera, 2 = shadow for padding.y light ID.
            if (input.padding.x == 0 || (input.padding.x == 1 && RaySurfaceVisible(primitive)) ||
                (input.padding.x == 2 && RayShadowAllowed(primitive, input.padding.y)))
                query.CommitNonOpaqueTriangleHit();
        }
    }

    RayHit result;
    result.hit = query.CommittedStatus() == COMMITTED_TRIANGLE_HIT ? 1 : 0;
    result.distance = result.hit ? query.CommittedRayT() : -1.0;
    result.instance = result.hit ? query.CommittedInstanceID() : 0xffffffff;
    result.primitive = result.hit ? query.CommittedPrimitiveIndex() : 0xffffffff;
    Hits[threadID.x] = result;
}
