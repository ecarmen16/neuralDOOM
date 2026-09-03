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

## D-006 - Preserve display-referred scene color before overlay GUI

**Status:** Accepted for the Phase 3 diagnostic and future composition boundary.

**Reasoning:** Source and RenderDoc evidence show that scene post-processing completes in `_currentRenderLDR` before `RC_DRAW_VIEW_GUI` mutates the same resource. Copying at that command boundary retains the final scene treatment while excluding overlay HUD and menu pixels.

**Consequence:** `_neuralHudlessLDR` is a native-resolution `R8G8B8A8_UNORM` snapshot. Debug mode `1` presents it after GUI execution to make separation directly observable. This decision does not select the linear/HDR input expected by a future temporal reconstruction backend.

## D-007 - Keep the first-person viewmodel in the shared scene with dedicated motion

**Status:** Accepted for the neural input path; OFF by default during development.

**Reasoning:** The weapon and hands are already present in HDR scene color and depth before TAA, while their `weaponDepthHack` surfaces are deliberately omitted from the existing fullscreen camera-vector draw. A separate color layer would require invasive pass reordering and duplicate lighting. Reusing the verified rigid/skinned velocity path with the viewmodel's depth-hacked projection supplies coherent geometry motion without changing scene composition.

**Consequence:** `r_neuralViewmodelMotionVectors` independently enables viewmodel vectors and is not forced by `r_neuralDebug`. Current and previous viewmodel projections receive the same depth hack used by scene rasterization. Existing motion-blur alpha rejection is unchanged. Reactive handling for muzzle flashes and unstable weapon effects remains a separate mask task.

## D-008 - Keep reactive and transparency classification independent

**Status:** Accepted for the engine temporal-input path; generation is OFF by default.

**Reasoning:** Combat captures proved that treating every nonopaque blend as transparency marks large additive and emissive portions of the world, destroying the mask's usefulness for temporal reconstruction. Those stages are unstable and belong in the broader reactive signal, while transparency is limited to conventional alpha composition, premultiplied-alpha composition, and nonopaque glass stages.

**Consequence:** The renderer owns two native-resolution `R8` resources: `_neuralReactiveMask` and `_neuralTransparencyMask`. Reactive classification includes translucent, additive/emissive, dynamic/cinematic, GUI/subview, and decal-or-later material work. Transparency is the narrower alpha/glass subset. Both are geometry- and texture-aware, combine overlaps with maximum blending, and are not yet consumed by TAA or a vendor backend.

## D-009 - Use one renderer-owned temporal-history epoch

**Status:** Accepted.

**Reasoning:** Camera matrices, TAA feedback, rigid transforms, and skinned palettes must invalidate on the same rendered frame. Clearing only the fullscreen TAA validity bit leaves object histories capable of emitting velocities across discontinuities. A monotonically increasing epoch can be captured into the frame-local view and compared by persistent entity histories without retaining frame-local GPU handles.

**Consequence:** Level/save loads, framebuffer recreation, render-world changes, major viewport/FOV changes, camera teleports/cuts, and manual requests advance one epoch. Exact engine events are preferred; conservative transform thresholds cover camera and object teleports where no explicit event exists. Camera animation cut frames set `RDF_CAMERA_CUT`. Portal-sky captures use `RDF_NO_TEMPORAL_HISTORY`: they resolve from the current frame for valid tonemapping but do not advance primary camera/TAA history.

## Pending decisions

- Whether and how a GPL-compatible public binary distribution can include or depend on the separately licensed NGX/DLSS runtime.

Resolve these only after `RECON_REPORT.md` and targeted captures provide evidence.

## D-010 - Put vendor implementations behind an NVRHI temporal-frame contract

**Status:** Accepted.

**Reasoning:** The verified inputs already exist as engine-owned NVRHI resources. Passing those handles with measured conventions, matrices, jitter, exposure, dimensions, sample count, and reset epoch keeps shared rendering independent of D3D12/NGX/Streamline while giving a native adapter everything needed at one insertion point.

**Consequence:** `neuralTemporalFrame_t` is the stable shared boundary. `idNeuralTemporalBackend` owns initialize/resize/reset/evaluate/shutdown behavior. The first implementation is a null/debug validator selected by `r_neuralBackend 1`; it always declines presentation and therefore falls back to existing TAA. Future vendor code must remain below this interface and behind an OFF-by-default build option.

## D-011 - Provision Streamline locally and use manual DX12 integration

**Status:** Accepted for private development; distribution blocked.

**Reasoning:** NVIDIA's official v2.12.0 guide recommends manual hooking when an engine needs native interfaces and compatibility with third-party rendering layers. RBDOOM and NVRHI already own device, queue, swapchain, and presentation lifecycles, so explicit proxy boundaries are safer than globally replacing platform APIs. The framework source is permissively licensed, but NGX/DLSS is separately licensed and its open-source restriction is not assumed compatible with RBDOOM's GPL.

**Consequence:** The official release zip is hash-pinned under ignored `local-proprietary/`. `USE_STREAMLINE` defaults OFF and requires an explicit `STREAMLINE_SDK_PATH`. No SDK source or binary is committed. The adapter must initialize before relevant DXGI calls, provide the native D3D12 device, use frame-based resource tagging, preserve NVRHI command-list state, and guarantee fallback. Public binary distribution remains prohibited by project policy until qualified license review resolves the conflict.

## D-012 - Prove DLAA at native resolution before adding DLSS scaling modes

**Status:** Accepted for the first official feature evaluation.

**Reasoning:** Native-resolution DLAA exercises the full official DLSS temporal contract and exposes incorrect depth, motion, jitter, reset, mask, exposure, and layer inputs without simultaneously changing render resolution. It gives a direct image-quality verdict against the established native TAA path before resolution plumbing expands the test surface.

**Consequence:** `r_neuralBackend 2` evaluates Streamline DLAA Preset K from linear HDR into the existing pre-tone-map `_taaResolved` target. NVIDIA auto exposure is used for this first slice; the engine exposure buffer remains in the neutral contract for later validation. A minimal `r_neuralBackend 3` Quality path exists only to prove cross-resolution extents and fallback. Full scaling-mode UX and tuning remain deferred because 100% source resolution is preferred for the planned neural-rendering experiment on the RTX 5090.
