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

**Consequence:** `r_neuralBackend 2` evaluates Streamline DLAA Preset K from linear HDR into the existing pre-tone-map `_taaResolved` target. NVIDIA auto exposure is used for this first slice; the engine exposure buffer remains in the neutral contract for later validation. A minimal `r_neuralBackend 3` Quality path exists only to prove cross-resolution extents and fallback. Full scaling-mode UX and tuning remain deferred because 100% source resolution is preferred for the planned neural-rendering experiment on the test GPU.

## D-013 - Brand the downstream project neuralDoom and keep dependencies layered

**Status:** Accepted.

**Reasoning:** The final project needs one recognizable install and launch surface while preserving the ability to update RBDOOM independently and remove experimental integrations. Retail data, community content, official SDK components, and experimental local validation files have different licenses and distribution rules and cannot be treated as one repository payload.

**Consequence:** The downstream CMake target and visible development version use `neuralDoom`, with explicit RBDOOM attribution retained. `Setup-NeuralDoom` assembles owned game data and verified optional content locally. A runtime selected by the user may be downloaded from an entered HTTPS URL or copied from a browsed local file into the ignored install directory; no runtime URL or binary is carried by the source repository or neuralDoom release.

## D-014 - Treat embedded ReShade startup as a removable compatibility bridge

**Status:** Accepted for local experimental validation only.

**Reasoning:** Public RHI source shows that it installs a ReShade graphics proxy and launches the target normally. Public ReShade supports loading under a non-proxy filename and exposes the add-on API requested dynamically by the local DLSS5 add-on. Loading that runtime from NeuralDoom before D3D12 creation removes the manual proxy installation step while preserving the complete device, swapchain, overlay, configuration, and add-on lifecycle that the closed experimental bridge expects. Reimplementing that private add-on or calling an undocumented NR runtime interface would be less supportable and would cross the project's legal/API boundary.

**Consequence:** `r_neuralCompatibilityEnable` defaults OFF and only loads an ignored, user-supplied `neuraldoom-reshade64.dll`. ReShade still performs D3D12 hooks internally; this is not described as a native Neural Rendering backend. The engine's neutral temporal contract and official Streamline backend remain independent. A later public, documented DLSSNR API replaces this bridge rather than inheriting its ReShade assumptions.


## D-015 - Use optional native scRGB with explicit SDR fallback

**Status:** Accepted for a prototype; actual HDR display review pending.

**Reasoning:** The renderer already has linear HDR scene inputs. Native Windows scRGB allows those highlights to survive into presentation without the temporary NR bridge. SDR LUTs, filmic scratch targets and retro modes require explicit handling to avoid silently clipping the new path.

**Consequence:** `r_hdrOutput 1` requests FP16 scRGB on DX12, while SDR remains the default. Scene reference white, peak and nominal UI white are separate saved controls. The prototype retains extended gamma-coded HUD composition, converts only the presentation blit to linear scRGB, and bounds SDR fallback. Legacy retro/CRT/SMAA content remains SDR; the embedded bridge retains 8-bit transport. A non-archived diagnostic tests HDR tone mapping without changing Windows display settings. See NATIVE_HDR.md for the exact formats and limitations.


## 2026-09-06 - Preserve native material energy when adding reflections

Capture the native probe specular layer and its material response during IBL shading, then blend ray hits into that layer. Keep probes for ray misses and unsupported receivers. This preserves native material roughness/normal maps and avoids unconditional extra specular light. For multi-stage materials, overwrite the three capture targets together and replace only that matching layer.

Share the existing static-world GI scene/material/light cache; do not duplicate its atlas or add a denoiser SDK. Filter incident radiance at full viewport resolution and apply current-pixel BRDF response afterward. Reuse engine temporal epochs with explicit normal/distance/roughness rejection. Keep compiled-out and feature-off fallbacks, and require offline shader permutation/output/binding checks alongside builds with separate manual visual validation.

Reduce default diffuse bounce strength 1.5 to 1.125 in response to the contrast review. Do not reduce render resolution. Rigid dynamic geometry is the next bounded scene-coverage task after reflection playtesting.
