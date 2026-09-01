# Decision log

## D-001 — Use RBDOOM-3-BFG as the primary implementation base

**Status:** Accepted for initial work.

**Reasoning:** It already provides a modern Windows DX12 path through NVRHI, avoiding an unnecessary renderer port. It is also a better fit for a native D3D12 NGX/Streamline experiment than beginning with the original OpenGL renderer.

**Consequence:** The initial project requires Doom 3 BFG Edition data. Original-Doom-3/dhewm3-family support may be investigated later.

## D-002 — Target DX12 first, without deleting Vulkan/shared abstractions

**Status:** Accepted.

**Reasoning:** DX12 is the direct route to the current D3D12 interception/integration ecosystem. The baseline build disables Vulkan to reduce setup complexity, but shared renderer code should remain backend-conscious.

**Consequence:** Native D3D12 handles belong in a narrow adapter beneath an engine-owned interface.

## D-003 — Separate the feeder proof of concept from the proper engine integration

**Status:** Accepted.

**Reasoning:** The feeder can answer whether the visual idea is compelling with little source work, but optical-flow motion vectors and post-HUD processing are not a dependable shipping architecture.

**Consequence:** No feeder or RenoDX dependency enters core source. POC findings inform priorities for real engine inputs.

## D-004 — Implement real temporal inputs before committing to a vendor backend

**Status:** Accepted.

**Reasoning:** Depth, motion vectors, jitter, exposure, resets, masks, and layer ordering are useful for DLSS, FSR, XeSS, TAA research, debugging, and future Neural Rendering. Vendor calls without correct inputs would create a misleading demo and technical debt.

**Consequence:** Native DLSS/Streamline integration is phase-gated behind temporal validation.

## D-005 — Only public, official SDKs may be tracked or distributed

**Status:** Accepted.

**Reasoning:** The current “DLSS 5” community path may involve a runtime extracted from commercial software or otherwise not intended for redistribution.

**Consequence:** Local experiments are user-supplied and untracked. Official SDK integration must pass dependency/license review.

## Pending decisions

- Exact scene-color stage used by the reconstruction backend.
- Viewmodel policy: after-pass, separate pass, or shared pass with dedicated inputs.
- Motion-vector format, units, sign, Y convention, and jitter treatment.
- Previous-pose storage strategy for MD5 animation.
- Reactive/transparency mask representation and material classification.
- Official Streamline acquisition mechanism and source-tree layout.

Resolve these only after `RECON_REPORT.md` and targeted captures provide evidence.
