# Implementation notes

Append dated entries. Do not replace prior evidence.

## 2026-09-02 - Preliminary cross-resolution DLSS Quality diagnostic

- Extended the Streamline backend selector with `r_neuralBackend 3` for a narrow DLSS Quality diagnostic. The renderer now reports the primary view's actual rendered viewport as the input extent while retaining the native `_taaResolved` output extent; mode `2` continues to require equal native dimensions for DLAA.
- Preset K Quality options, frame tags, history reset, fallback, and the existing temporal inputs are shared with DLAA. Option and history state reset when the active Streamline mode or output dimensions change.
- Both SDK-OFF and SDK-ON builds passed. A disposable `r_screenFraction 67` run reconstructed 857x482 into 1280x720 for 153 evaluated/presented frames with zero rejects and a clean shutdown.
- This capability is retained as infrastructure evidence, not the visual objective. The RTX 5090 already renders Doom 3 with ample headroom; the intended path remains 100% scene resolution so future neural rendering can consume maximum source detail.

Next: keep the normal runtime at mode `2`/100% and define the legally usable, documented NR evaluation boundary. Full mode UI, recommended-resolution selection, and performance tuning remain deferred.

## 2026-09-02 - Native-resolution Streamline DLAA vertical slice

- Added `neo/renderer/NeuralTemporalStreamline.cpp:idStreamlineNeuralTemporalBackend` and selected it with `r_neuralBackend 2`. Mode `0` remains disabled, mode `1` remains the null validator, and Streamline plus its local official runtime remain build-time optional and OFF by default.
- Extended `neuralTemporalFrame_t` with the unjittered camera projection, camera basis/position, near/far/FOV/aspect, and an engine frame index. `idRenderBackend::EvaluateNeuralTemporalBackend` fills those values from the rendered view; camera right is converted from idTech's left-axis convention.
- The adapter configures native-resolution `sl::DLSSMode::eDLAA` with transformer Preset K, HDR input, NVIDIA auto exposure, and alpha upscaling disabled. It submits row-major unjittered camera/reprojection matrices, pixel jitter, normalized pixel-motion scale, camera data, depth convention, and unified history reset state.
- Each evaluation transitions and tags `_currentRenderHDR` (`RGBA16_FLOAT`), `_currentDepth` (`D24_UNORM_S8_UINT`), `_taaMotionVectors` (`RG16_FLOAT`), both `R8_UNORM` classification masks, and UAV output `_taaResolved` (`RGBA16_FLOAT`). Tags use frame-based `eValidUntilEvaluate` lifetime. Streamline receives the native D3D12 command list, and NVRHI pipeline state is cleared after evaluation as required by the manual-hooking path.
- Any unavailable SDK/device, invalid/native-resolution mismatch, matrix failure, option/tag/constant failure, or evaluation failure returns `false`, preserving the established native TAA path. A gap in evaluated engine frame indices forces a DLSS history reset, making live mode `0`/`2` A/B toggles safe. Backend status reports evaluated, presented, and rejected counts plus the most recent result.
- Both `USE_STREAMLINE=OFF` and official-v2.12.0 `USE_STREAMLINE=ON` `RelWithDebInfo` builds passed. A disposable 1280x720 `game/mars_city2` run evaluated and presented 597 DLAA frames with zero rejects and exited cleanly. Existing missing-envprobe and reliable-message warnings were unchanged.

Visible saved-game A/B completed: the user found native TAA and DLAA difficult to distinguish, with no reported rendering regression. ND3-320 is complete as temporal-contract infrastructure; DLAA is not treated as the project's transformative visual feature.

## 2026-09-01 - Streamline core lifecycle and native DX12 device handoff

- Added `neo/renderer/StreamlineIntegration.h/.cpp`. With `USE_STREAMLINE=OFF` the entry points are dependency-free stubs. With the SDK build enabled, `r_streamlineEnable 1` initializes Streamline before `R_SetNewMode` can create the swapchain.
- Streamline preferences select manual hooking, frame-based resource tagging, host-managed command-list state, D3D12, a custom engine identity, and no OTA behavior. The experimental local path requests `kFeatureDLSS` with a stable project GUID and custom-engine identity even when `r_streamlineApplicationId` is `0`; an NVIDIA-issued ID remains a production/legal-support concern, not an implementation gate.
- After NVRHI device creation, `idRenderBackend::Init` retrieves `D3D12_Device` from NVRHI and passes it to `slSetD3DDevice`. A DLSS-requested path then checks support using the device adapter LUID. `streamlineStatus` reports compile/request/init/device/feature state and exact Streamline result strings.
- `idRenderBackend::Shutdown` now calls `slShutdown` after renderer resources are released but before `GLimp_Shutdown` destroys DXGI/D3D12. Any init/device failure logs a warning and retains the native renderer.
- The SDK-enabled build stages `sl.interposer.dll`, `sl.common.dll`, `sl.dlss.dll`, and `nvngx_dlss.dll` beside its ignored executable. No runtime binary enters Git or the normal build.
- Both SDK-OFF and SDK-ON `RelWithDebInfo` builds passed. Logged core-only startup recorded successful Streamline init and D3D12 device acceptance on the RTX 5090; an engine-driven `+quit` completed with exit code 0.

- The application-ID-zero probe succeeded: `slInit` loaded the requested DLSS feature using the experimental custom-engine/project identity, `slSetD3DDevice` accepted the RTX 5090, and `slIsFeatureSupported(kFeatureDLSS)` returned `eOk`. The scripted process exited normally with code 0.

Next: add the exact manual presentation hook and DLAA resource tagging/evaluation behind `r_neuralBackend 2`; defer NVIDIA application-ID paperwork to any future supported/released distribution.

## 2026-09-01 - Official Streamline 2.12.0 dependency gate

- NVIDIA's official GitHub release identifies v2.12.0 as current, published 2026-06-23. Annotated tag resolves to commit `e8aaa6eaac968711fb62473d4ae8256dde20919b`.
- Official release asset `streamline-sdk-v2.12.0.zip` was downloaded to ignored local storage and matched the vendor-published SHA-256 `F5C0A3D870707DDDC3570FB4BCD3655CF48A8A68C3A9D342910CFA21B77DCF48`.
- Streamline framework code uses an MIT-style license. NGX/DLSS files carry separate NVIDIA RTX SDK terms whose open-source-license limitation makes GPL binary redistribution unresolved; no SDK files enter Git and no distributable build is approved.
- Official v2.12.0 programming guides require early `slInit`, explicit D3D device setup, frame-based resource tagging, correct native resource states, command-list state restoration, and per-present housekeeping. D-011 selects manual DX12 integration around NVRHI ownership.
- `neo/CMakeLists.txt` now exposes `USE_STREAMLINE=OFF` and an empty `STREAMLINE_SDK_PATH`. Enabling it requires the official `include/sl.h` and x64 `sl.interposer.lib`; the normal build remains independent.
- The established default/OFF DX12 configure and `RelWithDebInfo` build passed. A separate ignored `build-streamline` tree configured and built with `USE_STREAMLINE=ON` against the hash-pinned local SDK; its executable is 19,822,080 bytes with SHA-256 `438ADEEA28C02512029026CF3DC40CBA8E34B97DC39AF0067BF926536A0568F4`.

Next: add the early-init/native-device adapter and explicit fallback without enabling DLSS evaluation yet.

## 2026-09-01 - Neutral temporal backend interface

### Repository state

- Branch: `feature/neural-rendering-spike`.
- Base checkpoint: `b4d2225a` (`renderer: unify temporal history resets`).
- Dirty before task: no.

### Files and symbols

- `neo/renderer/NeuralTemporal.h:neuralTemporalFrame_t` defines the engine-owned NVRHI resource and plain-metadata contract. `idNeuralTemporalBackend` defines explicit initialize, resize, reset, evaluate, status, and shutdown behavior.
- `neo/renderer/NeuralTemporal.cpp:idNullNeuralTemporalBackend` validates/consumes complete frames, records counters and lifecycle state, and always returns `false` so the established TAA path presents the frame.
- `neo/renderer/RenderBackend.cpp:idRenderBackend::EvaluateNeuralTemporalBackend` assembles the contract after masks and motion vectors and before TAA. `r_neuralBackend 1` forces full scene/object/skinned/viewmodel velocity and both masks; `0` is the default.
- `neo/renderer/Passes/TonemapPass.h:GetExposureBuffer` exposes the NVRHI adapted-exposure buffer without leaking native API handles.
- `neo/renderer/NVRHI/RenderBackend_NVRHI.cpp` and `Framebuffer_NVRHI.cpp` connect device init, resize, reset, and shutdown lifecycle.

### Contract and conventions

- Scene input/output: native-resolution linear HDR `RGBA16_FLOAT`, before tonemapping and overlay UI. Output is `_taaResolved`; returning `false` guarantees ordinary TAA fallback.
- Depth: native `D24_UNORM_S8_UINT`, device 0..1, non-reversed. Sample count is explicit.
- Velocity: native `RG16_FLOAT`, current-to-previous pixel displacement, +X right and +Y down. Previous unjittered MVP is captured before the velocity pass advances history.
- Jitter: current and previous offsets are supplied in render pixels. Reset state is both an exact per-frame boolean and a monotonically increasing epoch.
- Masks: native `R8_UNORM` reactive and transparency resources; validator mode forces fresh generation.
- Exposure: `exp2(r_exposure)` scalar plus the live one-element adapted-exposure NVRHI buffer and an automatic-exposure flag.

### Validation

- Configure and `RelWithDebInfo` build passed; new files were included and all DXIL remained current.
- Feature-off staged build remained alive for ten seconds with `r_neuralBackend 0`.
- Hidden DX12 validator test deliberately set `r_taaMotionVectors 0`, loaded `game/mars_city2`, consumed 177 frames with 0 rejected, reported epoch/reset propagation and matching 1725x985 render/output sizes, then exited with code 0.
- Visible saved-game validation consumed 1,076 frames with 0 rejected, epoch/reset epoch 4, and matching 1725x985 sizes. The user confirmed normal gameplay, weapon, HUD, and objective rendering through the unchanged TAA fallback.
- Staged executable: 24,773,632 bytes; SHA-256 `71ECE524E25533B168BB75AA0D8CFA262F7182DD5167A62D6BFA1F3087E9F886`.

### Next narrow task

- Re-verify the current official Streamline/DLSS SDK version, acquisition mechanism, licensing, and redistributable boundaries before adding an OFF-by-default build option.

## 2026-09-01 - Unified temporal-history reset lifecycle

### Repository state

- Branch: `feature/neural-rendering-spike`.
- Base checkpoint: `e6b0fed3` (`renderer: add temporal classification masks`).
- Dirty before task: no.

### Files and symbols

- `neo/renderer/RenderCommon.h:neuralTemporalResetReason_t` defines explicit reason bits and carries an epoch plus reset reasons in each frame-local `viewDef_t`.
- `neo/renderer/RenderSystem.cpp:idRenderSystemLocal::PrepareTemporalHistory` owns primary-view tracking, threshold detection, epoch advancement, named telemetry, and the last consumed reset record.
- `neo/renderer/RenderSystem_init.cpp` requests level-load resets, initializes the lifecycle, exposes conservative camera/object/FOV thresholds, and registers `neuralHistoryReset` plus `neuralHistoryStatus`.
- `neo/renderer/NVRHI/Framebuffer_NVRHI.cpp:Framebuffer::ResizeFramebuffers` requests a resize epoch and immediately invalidates backend feedback before any same-frame resized draw.
- `neo/renderer/RenderBackend.cpp:idRenderBackend::InvalidateTemporalHistory` invalidates both eye MVPs and TAA feedback validity. `DrawViewInternal` consumes frame-local reset reasons before motion vectors and temporal resolve.
- `neo/renderer/tr_frontend_addmodels.cpp:R_AddSingleModel` requires epoch continuity for rigid and joint-palette history and suppresses rigid velocity across object translations larger than the configured teleport threshold.
- `neo/d3xp/Camera.cpp:idCameraAnim::GetViewParms` maps authored cinematic cut frames to `RDF_CAMERA_CUT`.
- `neo/d3xp/PlayerView.cpp:idPlayerView::SingleView` marks portal-sky capture views `RDF_NO_TEMPORAL_HISTORY`; they receive a current-frame-only TAA resolve without changing primary history.

### Lifecycle contract

- Epoch changes invalidate TAA feedback, previous camera matrices, rigid transforms, skinned poses, and viewmodel histories on the same frame.
- Exact reset signals: renderer initialization, level/save load, framebuffer resize/device-mode recreation, render-world change, authored cinematic cut, and `neuralHistoryReset`.
- Detected discontinuities: primary-camera translation over 96 world units/frame, any camera basis rotation over 45 degrees/frame, viewport dimensions changing, or instantaneous horizontal/vertical FOV change over 5 degrees.
- Per-object translation over 64 world units/frame invalidates only that entity's rigid/skinned motion history; it does not flush unrelated scene history.
- Thresholds are runtime cvars and intentionally conservative: `r_neuralHistoryTeleportDistance`, `r_neuralHistoryObjectTeleportDistance`, `r_neuralHistoryCutAngle`, and `r_neuralHistoryFovThreshold`.
- `neuralHistoryStatus` reports current epoch, pending reasons, last consumed reasons/frame, and tracked-view validity. `r_neuralHistoryDebug 1` prints resets as they are consumed.

### Validation

- Build: pass, `RelWithDebInfo`; all 768 DXIL shaders current and the engine linked/staged successfully.
- Final staged executable: 24,764,928 bytes; SHA-256 `EDB8BB8641CCD35FB8078C4634813B3D11DAFC79FB03476099DE4FCE1D456E21`.
- Hidden DX12 map-load/manual sequence exited with code 0. Status advanced epoch 4 to 5 across `neuralHistoryReset`.
- Hidden viewport/FOV/teleport/restart sequences exited with code 0. Named status evidence recorded initialization/level-load/framebuffer-resize, `fov-change`, `camera-teleport|camera-cut`, and another framebuffer-restart epoch.
- Runtime logs are local and untracked under the engine save path: `temporal_history_sequence.log`, `temporal_history_transitions.log`, `temporal_history_camera.log`, `temporal_history_fov.log`, and `temporal_history_status.log`.
- Combined visible T15-T17 check passed. After save resume, FOV discontinuity, and `vid_restart`, the user confirmed stable rendering; `neuralHistoryStatus` reported epoch 6, pending none, last reset `framebuffer-resize`, and a valid tracked view.

### Known limitations

- Camera/object teleport detection is threshold-based where the game does not emit an exact event. Very small teleports may need a future explicit gameplay signal; unusually large legitimate single-frame motion may conservatively discard one history sample.
- Authored `.camera` cuts are exact, while arbitrary third-party scripted camera swaps fall back to world-space/FOV discontinuity detection.
- Stereo retains the upstream shared `prevViewsValid` boolean; per-eye MVPs reset together, but a future stereo-focused validation may justify per-eye feedback validity.

### Next narrow task

- Introduce the neutral temporal-input/backend interface with a no-SDK null/debug implementation and an unchanged disabled path.

## 2026-09-01 - Reactive and transparency classification masks

### Repository state

- Branch: `feature/neural-rendering-spike`.
- Base checkpoint: `99b03cf5` (`renderer: add viewmodel motion vectors`).
- Dirty before task: no.

### Files and symbols

- `neo/renderer/Image.h` and `Image_intrinsic.cpp` add `_neuralReactiveMask` and `_neuralTransparencyMask` as native-resolution `R8` images.
- `neo/renderer/Framebuffer.h` and `NVRHI/Framebuffer_NVRHI.cpp` create and resize one depth-attached framebuffer for each mask.
- `neo/renderer/RenderBackend.cpp:idRenderBackend::DrawTemporalMasks` conditionally generates both engine-owned resources before temporal resolve. `DrawTemporalMask` evaluates visible material stages, samples their actual coverage textures, and rasterizes rigid or GPU-skinned geometry.
- `neo/renderer/RenderBackend.cpp:r_neuralTemporalMasks` controls generation and defaults to `0`. `r_neuralDebug 3` and `4` force generation and present reactive red or transparency cyan after GUI rendering.
- `neo/renderer/RenderProgs.h/.cpp`, `neo/shaders/shaders.cfg`, and `neo/shaders/builtin/debug/neural_mask.*.hlsl` add rigid/skinned mask programs with existing texture-matrix and screen-texgen support.
- `neo/renderer/Passes/CommonPasses.*` and `neo/shaders/builtin/debug/temporal_mask.ps.hlsl` add explicit diagnostic presentation permutations.

### Data and classification contract

- Both resources are full native resolution, single-channel `R8`, cleared to zero each generated view, depth-tested against `_currentDepth`, and accumulated with maximum blending.
- Reactive coverage includes translucent materials, nonopaque blend stages (including additive/emissive), dynamic or cinematic stages, in-world GUI/subview geometry, and decal-or-later sorts.
- Transparency is intentionally narrower: conventional source-alpha composition, premultiplied-alpha composition, or a nonopaque stage on a translucent glass material.
- Alpha-composed stages use sampled alpha times evaluated stage alpha. Other reactive stages use sampled RGB intensity times the strongest evaluated stage RGB channel.
- Standard stages use their sampled silhouette. Cubemap texgens are skipped. Only GUI/subview surfaces receive a solid-geometry fallback; particle proxy quads never do.
- These resources are neutral engine inputs. No TAA, DLSS, Streamline, ReShade, or RenoDX dependency or consumption is introduced.

### Validation

- Configure: pass with the established VS2022 x64 DX12-only configuration.
- Build: pass, `RelWithDebInfo`; ShaderMake completed 768 DXIL tasks and the engine linked and staged successfully.
- Final staged executable: 24,756,736 bytes; SHA-256 `0C5F0FF4274C60AFAD213F0C254FCD215615D9F9BF14051CB8AF8AF449228294`.
- Reactive diagnostic: user verified localized red coverage for combat instability including muzzle/exhaust, smoke, and animated screens, without the earlier full particle-proxy rectangle.
- Transparency diagnostic: an initial broad cyan floor/world result was rejected. Three combat RenderDoc captures isolated additive/emissive material work; restricting the mask to alpha/premultiplied-alpha/glass composition removed that false coverage. User confirmed the corrected result: "nailed it."
- Capture evidence remains local and untracked: `captures/neural/renderdoc-masks/transparency_frame2422.rdc`, `transparency_frame2548.rdc`, and `transparency_frame2742.rdc`.
- Feature-off smoke: the staged DX12 process with `r_neuralDebug 0` and `r_neuralTemporalMasks 0` remained alive after ten seconds and closed normally.

### Known limitations

- Classification is a material heuristic, not an authored semantic tag. Unusual custom blend equations may need targeted rules when observed.
- Cubemap/custom render-proc coverage is not sampled by the mask shader. The GUI/subview fallback preserves exact geometry only.
- Two `R8` resources are allocated even while generation is disabled; the feature-off path performs no mask clears or draws.
- Diagnostic presentation overwrites the final swapchain after GUI, so the console can be open but invisible in modes `3` and `4`.
- Masks are not yet consumed by the existing TAA pass or any neutral/vendor interface.

### Next narrow task

- Implement one explicit history-reset lifecycle covering map loads, camera cuts/teleports, resolution changes, and large FOV discontinuities before exposing the temporal input bundle through a neutral backend interface.

## 2026-09-01 - First-person viewmodel motion policy

### Repository state

- Branch: `feature/neural-rendering-spike`.
- Base checkpoint: `442c0427` (`renderer: add skinned object motion vectors`).
- Dirty before task: no.

### Files and symbols

- `neo/renderer/RenderBackend.cpp:r_neuralViewmodelMotionVectors` adds an independent OFF-by-default viewmodel switch that diagnostic mode `2` does not force.
- `neo/renderer/RenderBackend.cpp:idRenderBackend::DrawMotionVectors` admits `weaponDepthHack` surfaces only when that switch is enabled, reuses rigid/skinned object history, and applies the viewmodel depth hack to both current and previous motion projections.
- `neo/renderer/tr_frontend_addmodels.cpp:R_AddSingleModel` captures a viewmodel joint palette when the independent switch is enabled, even if world-skinned vectors and diagnostics are disabled.
- `neo/renderer/RenderCommon.h` exposes the cvar to the frontend.
- `docs/neural-rendering/DECISIONS.md:D-007` selects shared scene color/depth with dedicated viewmodel velocity for the future neural input path.

### Data and ordering contract

- The first-person weapon remains in the ordinary HDR scene color and current depth buffers; it is not split into a second lighting/composition pass.
- Viewmodel velocity uses the same current-to-previous pixel units, `R16G16_FLOAT` target, joint palettes, and root-transform history as world geometry.
- The current unjittered and previous object MVPs receive `idRenderMatrix::ApplyDepthHack` before the depth-equal velocity draw, matching the weapon's scene-depth placement.
- Existing motion-blur alpha rejection remains unchanged. This slice changes motion-vector generation only.
- `r_neuralViewmodelMotionVectors 0` preserves the previous neutral-vector behavior and performs no viewmodel-only history work. `1` enables both runtime vectors and mode-2 visualization.

### Validation

- Configure: pass with the established VS2022 x64 DX12-only options.
- Build: pass, `RelWithDebInfo`; all 758 DXIL shaders were current and C++ linked successfully.
- Final staged executable: 24,747,520 bytes; SHA-256 `EE673ABDA9566656B5DCE3344C519478636793E6E5A6F632F64F9A5BF6436167`.
- User T08 validation: on disposable `devmap game/mars_city2`, a granted weapon rendered normally, then produced coherent diagnostic motion during the combined walk/turn/fire test with no reported disappearance, depth flicker, trails, or crash.
- Feature-off smoke: the staged DX12 process with `r_neuralDebug 0` and `r_neuralViewmodelMotionVectors 0` remained alive after ten seconds and closed normally.

### Known limitations

- The opening Mars City save enforces a scripted no-weapon state even after inventory grant; `game/mars_city2` is the reproducible T08 test map.
- Only opaque viewmodel surfaces receive geometry velocity. Muzzle flashes and other translucent/unstable weapon effects require reactive classification.
- The switch remains off by default until the neutral temporal interface owns the input policy.

### Next narrow task

- Add engine-owned reactive/transparency classification resources for muzzle flashes, particles, glass, animated emissives, and in-world GUI content.

## 2026-09-01 - Skinned-object motion vectors

### Repository state

- Branch: `feature/neural-rendering-spike`.
- Base checkpoint: `e63f0bb9` (`renderer: add rigid object motion vectors`).
- Dirty before task: no.

### Files and symbols

- `neo/renderer/RenderCommon.h:idRenderEntityLocal` retains current and previous CPU joint palettes; `viewEntity_t` receives a frame-local previous-palette handle plus validity and movement flags.
- `neo/renderer/RenderEntity.cpp:idRenderEntityLocal::idRenderEntityLocal` initializes joint history invalid.
- `neo/renderer/tr_frontend_addmodels.cpp:R_AddSingleModel` finds the visible GPU-skinned palette, advances it once per consecutive renderer frame, and uploads the previous palette into the current frame's joint cache.
- `neo/renderer/RenderProgs.h/.cpp` adds `BUILTIN_SKINNED_MOTION_VECTORS` and a dedicated layout containing current joints at `t11` and previous joints at `t12`.
- `neo/renderer/NVRHI/RenderBackend_NVRHI.cpp:idRenderBackend::DrawElementsWithCounters` resolves both frame-local joint handles and builds the matching NVRHI binding set.
- `neo/renderer/RenderBackend.cpp:DrawMotionVectors` now overlays opaque rigid and GPU-skinned object velocity in one pass, selecting the appropriate shader per surface.
- `neo/shaders/builtin/debug/rigid_motion_vectors.vs.hlsl` has rigid and skinned permutations; the skinned permutation evaluates each vertex against both palettes before current/previous clip projection.
- `neo/shaders/shaders.cfg` builds both skinning and push-constant permutations.

### Data and ordering contract

- Each `idJointMat` contributes three `float4` rows. The current palette remains the existing `t11` buffer; the prior visible palette is a new `t12` buffer.
- Persistent history contains CPU matrices only. GPU joint-cache handles remain frame-local and are never retained across frames.
- Joint history is valid only for consecutive `tr.frameCount` samples with the same padded joint count. First observation, reappearance, or a count change emits no pose velocity.
- Current vertices use the current palette and current unjittered object MVP. Previous vertices use the previous palette and `previousViewMVP * previousModelRenderMatrix`.
- Output remains current-to-previous pixel displacement in native-resolution `R16G16_FLOAT`, matching the camera and rigid paths.
- Opaque GPU-skinned surfaces draw when either their palette or root model transform changed. GUI, viewmodel, subview, perforated, and translucent policy remains unchanged.
- `r_neuralSkinnedMotionVectors` defaults to `0`; `r_neuralDebug 2` forces it. With both controls off, no joint-history scan, copy, upload, or skinned velocity draw occurs.

### Validation

- Configure: pass with the established VS2022 x64 DX12-only options.
- Build: pass, `RelWithDebInfo`; ShaderMake completed 758 DXIL jobs and C++ linked successfully.
- Final staged executable: 24,747,008 bytes; SHA-256 `A77F5FF4E870C7461807AB3AAB04A06841605BB0660DB20CA3BB8918F62DD923`.
- Static-camera user validation: a talking marine produced subtle independent signed-color shimmer on animated helmet/body triangles while most static pixels remained neutral gray.
- Moving-camera user validation: forward motion and mouse rotation retained the established coherent camera field, with the animated contribution remaining stable and no reported corruption or crash.
- Feature-off smoke: the staged DX12 process with `r_neuralDebug 0` and `r_neuralSkinnedMotionVectors 0` remained alive after ten seconds and closed normally.

### Known limitations

- Only opaque GPU-skinned surfaces participate. Alpha-tested hair/grates, translucent effects, CPU deforms, and decals are not yet represented by this pass.
- Idle conversational animation often moves less than one pixel per frame and therefore appears deliberately subtle in the fixed `[-8, 8]` diagnostic range.
- Previous-palette uploads increase transient joint-cache use for visible tracked actors; a crowded multi-character scene has not yet been capacity-tested or timed.
- Explicit cut, teleport, map, FOV, and resolution reset signals remain a later lifecycle task.

### Next narrow task

- Resolve and implement the first-person viewmodel ordering/velocity policy, keeping its contribution independently switchable from world geometry.

## 2026-09-01 - Rigid-object motion vectors

### Repository state

- Branch: `feature/neural-rendering-spike`.
- Base checkpoint: `c9c5e063` (`renderer: add signed motion-vector diagnostic`).
- Dirty before task: no.

### Files and symbols

- `neo/renderer/RenderCommon.h:idRenderEntityLocal` retains current and previous rigid model matrices plus the sampled renderer frame; `viewEntity_t` receives an SMP-safe previous-transform snapshot and validity/movement flags.
- `neo/renderer/RenderEntity.cpp:idRenderEntityLocal::idRenderEntityLocal` initializes the new history state invalid, preventing first-frame velocity.
- `neo/renderer/tr_frontend_addmodels.cpp:R_AddSingleModel` advances history once per consecutive renderer frame and collapses stale/reappearing history to the current transform.
- `neo/renderer/RenderBackend.cpp:DrawMotionVectors` overlays moved opaque, non-skinned draw surfaces into `_taaMotionVectors` using the previous camera MVP and previous object transform.
- `neo/renderer/NVRHI/Framebuffer_NVRHI.cpp:Framebuffer::ResizeFramebuffers` attaches `_currentDepth` read-only to the motion framebuffer for depth-equal rigid coverage.
- `neo/renderer/RenderProgs.h/.cpp:BUILTIN_RIGID_MOTION_VECTORS` and `neo/shaders/builtin/debug/rigid_motion_vectors.*.hlsl` provide the geometry velocity program.
- `neo/shaders/shaders.cfg` builds push-constant and constant-buffer variants of both shader stages.

### Data and ordering contract

- Rigid history is keyed to `tr.frameCount`; only consecutive rendered frames are valid. New entities and entities absent for one or more frames emit no object-local velocity on reappearance.
- The vertex shader rasterizes with the current unjittered object MVP and projects the same local vertex with `previousViewMVP * previousModelRenderMatrix`.
- The pixel shader writes `previousWindowPosition - currentWindowPosition` in pixel units, preserving the existing current-to-previous convention and `R16G16_FLOAT` format.
- The overlay runs after the camera/depth reconstruction pass and uses current scene depth with equality testing. It is limited to opaque, non-skinned, non-GUI, non-viewmodel surfaces without subviews.
- `r_neuralRigidMotionVectors` defaults to `0`; diagnostic mode `r_neuralDebug 2` forces the overlay. The default feature-off path therefore retains the prior camera-only vector behavior.

### Validation

- Configure: pass with the established VS2022 x64 DX12-only options.
- Build: pass, `RelWithDebInfo`; ShaderMake completed 754 DXIL jobs, including both variants of each rigid-vector shader stage.
- Final staged executable: 24,737,280 bytes; SHA-256 `745BB38CFE724F43378EAC09E9C7B72548D722F35224CDEF0F072113835D363C`.
- User diagnostic validation: with a stationary camera, static surroundings remained neutral and a moving rigid object produced a distinct colored silhouette; no crash occurred.
- User physics validation: a free rigid prop produced object-local velocity while moving, returned to neutral after settling, and left no reported persistent trail.
- User feature-off validation: ordinary scene, HUD, menu, and gameplay rendering passed with `r_neuralDebug 0`.

### Known limitations

- Perforated and translucent materials are deliberately excluded because this slice does not yet reproduce material alpha testing.
- Skinned surfaces are deliberately excluded; only rigid model-transform motion is represented.
- Subpixel edge coverage can differ from the jittered depth raster because the velocity geometry uses the unjittered current MVP.
- History reset policy beyond non-consecutive entity visibility remains a later lifecycle task.

### Next narrow task

- Retain the previous GPU joint palette for visible MD5 surfaces and add a skinned velocity shader without changing the verified rigid path.

## 2026-09-01 - Signed motion-vector diagnostic

### Repository state

- Branch: `feature/neural-rendering-spike`.
- Base checkpoint: `d6d361fa` (`renderer: add HUD-free LDR diagnostic`).
- Dirty before task: no.

### Files and symbols

- `neo/renderer/RenderBackend.cpp:r_neuralDebug` adds mode `2`; `idRenderBackend::ExecuteBackEndCommands` presents `_taaMotionVectors` after GUI, and `DrawMotionVectors` generates the buffer in this diagnostic mode even when TAA and motion blur are disabled.
- `neo/renderer/Passes/CommonPasses.h/.cpp:BlitSampler::MotionVectors` selects a dedicated fullscreen debug pixel shader while reusing the existing blit vertex shader, binding layout, sampler, and pipeline cache.
- `neo/shaders/builtin/debug/motion_vectors.ps.hlsl` maps signed X/Y displacement into visible R/G channels.
- `neo/shaders/shaders.cfg` includes the diagnostic shader in the normal ShaderMake build.

### Visualization contract

- Input remains `_taaMotionVectors`: native-resolution, one-sample `DXGI_FORMAT_R16G16_FLOAT` current-pixel to previous-pixel displacement in pixel units.
- The shader clamps each component to `[-8, 8]`, maps X to red and Y to green using `encoded = motion * (0.5 / 8.0) + 0.5`, holds blue at `0.5`, and outputs alpha `1.0`.
- Neutral gray therefore represents `(0, 0)`. Direction changes the red/green balance; saturation indicates a component reached at least eight pixels of displacement.
- Mode `2` is display-only. It does not modify the stored vectors or their TAA consumer.

### Validation

- Configure: pass with the established VS2022 x64 DX12-only options.
- Build: pass, `RelWithDebInfo`; ShaderMake completed 750 DXIL jobs including `builtin/debug/motion_vectors.ps.hlsl`.
- Staged executable SHA-256: `44F8D73B9F574EC680BAD2B2556219CA5E878C827F61FDAE0C1F7A9017DDDFE6`.
- User runtime validation: a static camera produced neutral gray; slow yaw produced a coherent signed field; lateral movement produced depth-dependent parallax; the excluded first-person weapon remained neutral.
- Feature-off regression: user loaded the saved game with `r_neuralDebug 0` and confirmed normal world, HUD, menus, and gameplay with no crash.
- RenderDoc capture: ignored `captures/neural/renderdoc-motion-debug/motion_debug_frame1811.rdc`, 483,723,622 bytes, SHA-256 `F3399F9FE722A2DB5EFAA9CB11E5A112C38526D116138CBE889EAF5C47D49479`.
- Capture evidence: `_taaMotionVectors` is `R16G16_FLOAT`; `Render_MotionVectors` precedes `Neural_PresentMotionVectors`; the captured 1725x985 debug output contains the expected smooth signed camera field.

### Known issues

- Current vectors describe camera/static-world motion only. Rigid and skinned objects do not retain previous object or pose transforms.
- The first-person weapon is deliberately excluded from the existing temporal mask and appears neutral in mode `2`; the final viewmodel policy remains pending.
- The diagnostic uses a fixed eight-pixel component range. A later numeric inspection mode may add adjustable scale or per-pixel values if needed.

### Next narrow task

- Add previous-transform history for one reproducible rigid-object class and validate it against a moving door/lift or physics object with a static camera.

## 2026-09-01 - HUD-free LDR diagnostic

### Repository state

- Branch: `feature/neural-rendering-spike`.
- Base checkpoint: `992b6355` (`docs: record DX12 temporal capture evidence`).
- Dirty before task: no.

### Files and symbols

- `neo/renderer/Image.h:idImageManager::neuralHudlessLDRImage` owns the preserved scene-only texture handle.
- `neo/renderer/Image_intrinsic.cpp:idImageManager::CreateIntrinsicImages` creates `_neuralHudlessLDR` with the existing `R_LdrNativeImage` generator.
- `neo/renderer/NVRHI/Framebuffer_NVRHI.cpp:Framebuffer::ReloadImages` recreates the texture with the other native-resolution targets.
- `neo/renderer/RenderBackend.cpp:idRenderBackend::ExecuteBackEndCommands` snapshots `_currentRenderLDR` after `RC_POST_PROCESS`, before `RC_DRAW_VIEW_GUI`, and presents the snapshot after all overlay GUI work when `r_neuralDebug` is `1`.

### Resource and mode contract

- `_neuralHudlessLDR`: native render resolution, one mip, one sample, `DXGI_FORMAT_R8G8B8A8_UNORM`, display-referred/post-processed LDR.
- Lifetime: intrinsic renderer image; resized through `Framebuffer::ReloadImages`; contents are refreshed once per applicable 3D frame only when debug mode `1` is active.
- `r_neuralDebug 0` is the default. It performs no per-frame snapshot or debug-present work and preserves normal composition.
- `r_neuralDebug 1` copies `_currentRenderLDR` after scene post-processing, allows GUI commands to execute normally, then overwrites the swapchain with the preserved scene-only copy. In-world GUIs and the first-person weapon remain because they are part of the 3D view; overlay HUD and menus are excluded.

### Validation

- Configure: pass with VS2022 x64 and the established DX12-only options.
- Build: pass, `RelWithDebInfo`; staged executable is 24,733,696 bytes with SHA-256 `7CF004A5F949E743E6D137B1685F60B00E3BD995773FA2FBDE30D9C4080B59C3`.
- Feature off: user loaded the saved scene with `r_neuralDebug 0` and confirmed normal gameplay, HUD, and menus with no rendering regression.
- Feature on: user loaded the same scene with `r_neuralDebug 1` and confirmed the world and weapon rendered normally while overlay GUI was absent.
- Live resize: user resized the window during mode `1`; the HUD-free scene continued rendering without a black frame, corruption, or crash.
- RenderDoc 1.46 capture: ignored `captures/neural/renderdoc-hudless/hudless_frame1567.rdc`, 431,617,464 bytes, SHA-256 `08F4925EE8A9F28CE89FAF4525959AF9B73FF8F0D8DE367EAE6374A0029F0B40`.
- Captured command order is `Render_PostProcessing` -> `Neural_CaptureHudlessLDR` -> `Render_DrawViewGUI` -> `Neural_PresentHudlessLDR`. The capture records a full 1280x720 `CopyTextureRegion` from `_currentRenderLDR` (resource 413) to `_neuralHudlessLDR` (resource 414), including NVRHI-generated copy-source/copy-destination transitions.

### Known issues

- The intrinsic texture is allocated even in mode `0` (3,686,400 bytes at 1280x720), although no disabled-mode copy or presentation work occurs.
- This establishes a display-referred HUD-free output. It does not yet select the linear/HDR input stage for DLSS or define the final first-person weapon policy.
- No comparative GPU timing has been recorded.

### Next narrow task

- Extend the diagnostic modes with a signed motion-vector view and numeric convention evidence for static camera, yaw, and lateral translation before changing the existing camera/static vector generation.

## 2026-08-31 - DX12 baseline and reconnaissance

### Repository state

- Branch: `feature/neural-rendering-spike`.
- Upstream commit: `ea29c006e84fedcc0e7c173c383a087ce0a8c0d5`.
- The initial clone was clean. This checkpoint adds only project instructions, documentation, and helper scripts; no renderer, shader, game-code, or CMake dependency-list files were edited.

### Environment

- Windows 10 IoT Enterprise LTSC 2024 build 26100.
- NVIDIA GeForce RTX 5090, driver 610.47.
- Visual Studio 2022 Community; MSVC 19.43.34810.0 / toolset 14.43.34808.
- CMake 3.30.5-msvc23 from the Visual Studio installation, discovered per process by the helper scripts; no System PATH change required.
- ISPC 1.31.0 (`c6adb4f`), local/ignored.
- Windows SDK DXC 1.7.2308.16.
- Build: DX12-only `RelWithDebInfo`.

### Commands

```powershell
.\tools\neural-rendering\Check-Prerequisites.ps1
.\tools\neural-rendering\Configure-RBDOOM-DX12.ps1
.\tools\neural-rendering\Build-RBDOOM.ps1 -Configuration RelWithDebInfo -StageExecutable
.\tools\neural-rendering\Run-RBDOOM.ps1
.\tools\neural-rendering\Capture-BaselineMetadata.ps1
```

### Findings

- The active frame path, temporal resources, formats, conventions, native D3D12 escape points, and gaps are documented in `RECON_REPORT.md`.
- Existing TAA motion is camera-only, current-to-previous displacement in pixel units.
- `_currentRenderHDR` is the pre-tonemap scene candidate. `_currentRenderLDR` remains HUD-free through scene post-processing; later GUI commands mutate it.
- Existing history validity is initialized once and is not explicitly reset for map/camera/resolution discontinuities.
- The first-person weapon is rendered in the 3D scene but excluded from TAA history via the HDR alpha mask.
- The modern tone-map pass always computes adapted luminance even though `r_hdrAutoExposure` defaults off; this requires capture/readback validation before an exposure contract is defined.

### Helper-script corrections

- `Common.ps1`: discover Visual Studio CMake and safe full paths; corrected an existing PowerShell interpolation parser error.
- `Check-Prerequisites.ps1`: made standalone Codex CLI optional for an active Codex session and added constrained-language-compatible Windows/submodule checks.
- `Configure-RBDOOM-DX12.ps1`: discover Windows SDK DXC, pass `DXC_CUSTOM_PATH`, and apply the narrow MSVC `/wd4530` ShaderMake compatibility flag.
- `Install-GameData.ps1`, `Install-ISPC.ps1`, `Bootstrap-NeuralDoom3.ps1`, and `Capture-BaselineMetadata.ps1`: avoid constrained-language-incompatible path/registry calls.
- `.gitignore`: expose only `tools/neural-rendering/**` from upstream's ignored `/tools/` directory. Local ISPC remains ignored.

### Validation

- Prerequisite gate: pass, including four initialized submodules and 64 local `.resources` candidates.
- Configure: pass with VS2022 x64 and DX12-only options.
- Build: pass; 749 DXIL shader jobs plus the engine executable.
- Executable: 24,732,160 bytes; SHA-256 `8EEF627AA8B7BEDA5E89FFD2410C3E94B549530CC01F45484FCEB7D46946F2BA`.
- Runtime: user visually confirmed DX12, started a new game, observed correct rendering, and created a resumable save; process then exited cleanly.
- RenderDoc 1.46 installed locally. Complete stationary and forward-motion DX12 frames were captured from the saved Mars City Hangar scene.
- Capture verified HDR `R16G16B16A16_FLOAT`, depth `D24_UNORM_S8_UINT`, LDR `R8G8B8A8_UNORM`, and motion `R16G16_FLOAT` at 1280x720 and 1x sampling where applicable.
- Signed forward-motion visualization confirmed current-to-previous vectors converging toward the vanishing point. Static capture correctly left the motion target cleared to zero.
- Event ordering confirmed scene post-processing completes before the GUI standard-shader stage mutates `_currentRenderLDR`.

### Known issues

- A repeatable Mars City Hangar save and capture position exist; a full console cvar dump has not yet been recorded.
- `RelWithDebInfo` links debug Visual C++ runtime DLLs and is not a redistribution build.
- Runtime validation did not yet cover the full static/motion/transparency/camera-cut matrix.

### Next narrow task

- Implement and validate an OFF-by-default diagnostic output-separation scaffold after scene post-processing and before GUI rendering; keep the disabled path pixel-equivalent.

## 2026-08-30 — Starter prepared

- Primary target: RBDOOM-3-BFG, Windows x64, DX12/NVRHI.
- Baseline configuration: `-DFFMPEG=OFF -DBINKDEC=ON -DUSE_DX12=ON -DUSE_VULKAN=OFF`.
- No source clone, build, or runtime validation was performed on the user's Windows machine by this starter-pack generator.
- First session is intentionally renderer-code-free and should create `RECON_REPORT.md`.

## Entry template

```markdown
## YYYY-MM-DD — Short task name

### Repository state
- Branch:
- Commit:
- Dirty before task: yes/no

### Environment
- Windows:
- GPU / driver:
- Visual Studio toolset:
- CMake:
- ISPC:
- Build configuration:

### Commands
```powershell
# exact commands
```

### Findings
- Exact paths/symbols:
- Formats/conventions:
- Pass/lifetime notes:

### Validation
- Build result:
- Runtime scenario:
- Debug/capture evidence:

### Known issues
-

### Next narrow task
-
```
