// SPDX-License-Identifier: GPL-3.0-or-later
// One uint2 per triangle: shadow-only flag and exact excluded light ID.
StructuredBuffer<uint2> RayShadowPolicies : register(t12);
bool RaySurfaceVisible(uint primitive)
{
    return RayShadowPolicies[primitive].x == 0;
}
bool RayShadowAllowed(uint primitive, uint lightID)
{
    uint excluded = RayShadowPolicies[primitive].y;
    return excluded == 0 || excluded != lightID;
}
