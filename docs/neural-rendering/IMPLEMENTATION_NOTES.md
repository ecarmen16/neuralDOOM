# Implementation notes

Append dated entries. Do not replace prior evidence.

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
