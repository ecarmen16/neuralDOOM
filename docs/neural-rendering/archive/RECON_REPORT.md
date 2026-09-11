# Renderer reconnaissance report

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../README.md) for current guidance.

Date: 2026-08-31

Branch: `feature/neural-rendering-spike`

Upstream commit: `ea29c006e84fedcc0e7c173c383a087ce0a8c0d5`

Scope: first-session, read-only renderer reconnaissance plus build/helper documentation

## Executive result

The unmodified upstream renderer configured and built as a DX12-only `RelWithDebInfo` target, then launched successfully against locally staged user-owned Doom 3 BFG data. Manual playtesting confirmed that a new game rendered through DX12 and created a resumable save. No renderer C/C++, shader, game-code, or CMake dependency-list files were changed.

The renderer already has most of the raw resources needed for an eventual temporal upscaler: pre-tonemap HDR color, depth, jittered and unjittered matrices, camera reprojection vectors, two feedback images, and a post-tonemap LDR image. It does **not** yet have complete motion: the existing velocity pass is camera-only, retains no previous rigid transforms or previous skinned poses, and has no proven discontinuity reset lifecycle. The first safe code task is therefore diagnostic output separation and capture, not an SDK call.

## Baseline proof

### Repository and platform

- Windows 10 IoT Enterprise LTSC 2024, build 26100.
- Visual Studio 2022 Community, MSVC 19.43.34810.0 / toolset 14.43.34808.
- Visual Studio-bundled CMake 3.30.5-msvc23. A system-wide PATH edit is unnecessary because `tools/neural-rendering/Common.ps1` discovers it for each project command.
- ISPC 1.31.0, installed under ignored local path `tools/ispc/bin/ispc.exe`; archive SHA-256 is recorded in `THIRD_PARTY_AND_LEGAL.md`.
- NVIDIA GeForce RTX 5090, driver 610.47.
- Upstream submodules were initialized at the SHAs recorded in `UPSTREAM_BASE.txt` and the prerequisite report.

### Configuration and build

The effective configuration was:

```text
-DFFMPEG=OFF
-DBINKDEC=ON
-DUSE_DX12=ON
-DUSE_VULKAN=OFF
-DCMAKE_CXX_FLAGS=/wd4530
-DDXC_CUSTOM_PATH=<Windows SDK 10.0.26100.0 x64 bin>
```

`/wd4530` is a local configure compatibility flag, not an upstream source edit. ShaderMake treats warnings as errors, while the installed MSVC emits C4530 from standard-library headers when compiling with upstream exception settings. Suppressing that one diagnostic preserved upstream exception behavior and allowed ShaderMake to build.

Build command:

```powershell
.\tools\neural-rendering\Build-RBDOOM.ps1 -Configuration RelWithDebInfo -StageExecutable
```

Result:

- Target: `RBDoom3BFG.exe`, declared by `APP_NAME` and `add_executable` in `neo/CMakeLists.txt`.
- Build output: `build/RelWithDebInfo/RBDoom3BFG.exe`.
- Staged output: repository-root `RBDoom3BFG.exe`.
- Size: 24,732,160 bytes.
- SHA-256 of both copies: `8EEF627AA8B7BEDA5E89FFD2410C3E94B549530CC01F45484FCEB7D46946F2BA`.
- ShaderMake completed 749 DXIL shader tasks; the Windows SDK DXC reported version 1.7.2308.16.
- `dumpbin /dependents` found only Windows and debug Visual C++ runtime DLL dependencies. The `RelWithDebInfo` executable currently links `MSVCP140D.dll`, `VCRUNTIME140D.dll`, `VCRUNTIME140_1D.dll`, and `ucrtbased.dll`, so this build is a development-machine baseline rather than a redistributable package.

Runtime command:

```powershell
.\tools\neural-rendering\Run-RBDOOM.ps1
```

The helper launched with `+set r_graphicsAPI dx12`. Manual playtesting confirmed DX12, entered a new game, observed correct rendering, and created a resumable save. Local metadata is under the ignored path `captures/neural/20260831-220206/baseline-metadata.md`.

## Frame flow

```text
game view + weapon -> gameRenderWorld->RenderScene
  -> R_RenderView (frontend visibility, matrices, draw surfaces)
  -> RC_DRAW_VIEW_3D
  -> DrawViewInternal (HDR scene passes)
  -> camera motion vectors -> TAA resolve -> tone map to _ldr
  -> blit _ldr to DX12 swapchain

HUD / screen effects / console / menu -> guiModel
  -> EmitFullScreen -> RC_DRAW_VIEW_GUI
  -> DrawViewInternal (2D into _ldr)
  -> blit updated _ldr to DX12 swapchain

backend closes/submits NVRHI command list -> Present
```

### Frontend and command construction

- `neo/d3xp/PlayerView.cpp:idPlayerView::SingleView` calls the world renderer through `fxManager->Process`, which renders the hacked player view, before queuing screen blobs and `player->DrawHUD`.
- `neo/renderer/tr_frontend_main.cpp:R_RenderView` assigns `taaFrameCount`, builds jittered and unjittered projection/MVP matrices, determines visibility, adds lights/models/in-world GUIs/subviews, and calls `R_AddDrawViewCmd`.
- `neo/renderer/RenderSystem.cpp:R_AddDrawViewCmd` emits `RC_DRAW_VIEW_3D` or `RC_DRAW_VIEW_GUI`.
- `neo/renderer/RenderSystem.cpp:idRenderSystemLocal::SwapCommandBuffers_FinishCommandBuffers` calls `guiModel->EmitFullScreen`, which packages pending 2D surfaces at the end of frontend command generation.
- `neo/renderer/GuiModel.cpp:idGuiModel::EmitFullScreen` constructs `is2Dgui = true` and calls `R_AddDrawViewCmd(viewDef, true)`.

### Backend and pass order

- `neo/renderer/RenderSystem.cpp:idRenderSystemLocal::RenderCommandBuffers` hands command buffers to `idRenderBackend::ExecuteBackEndCommands`.
- `neo/renderer/RenderBackend.cpp:idRenderBackend::ExecuteBackEndCommands` starts the frame, iterates 3D, GUI, copy, and post-process commands in order, then ends the frame.
- `neo/renderer/RenderBackend.cpp:idRenderBackend::DrawViewInternal` binds `_hdr` for a 3D view or `_ldr` for ordinary 2D. The observed 3D order is depth prepass, Hi-Z, geometry buffer, SSAO, ambient/static light, shadow atlas, light interactions, generic/emissive surfaces, fog/blend lights, screen-warp post surfaces, debug tools, motion vectors, TAA, tone mapping to `_ldr`, then swapchain blit.
- An ordinary GUI command subsequently binds `_ldr`, draws 2D surfaces into it, and blits the updated image to the swapchain. RenderDoc additionally confirms a scene post-processing region between the first scene blit and GUI. Therefore the strongest final-LDR HUD-free boundary is after scene post-processing and immediately before the GUI `Standard Shader Stage`; `_ldr` is mutated by GUI rendering after that boundary and must be captured or copied there.
- The first-person weapon is part of the 3D scene before TAA/tone mapping. `neo/d3xp/Weapon.cpp` sets `renderEntity.weaponDepthHack`; `neo/renderer/tr_frontend_addmodels.cpp` propagates it to `viewEntity_t` and applies the depth hack to its MVP.

### Command submission and present

- `neo/renderer/NVRHI/RenderBackend_NVRHI.cpp:idRenderBackend::GL_StartFrame` calls `DeviceManager::BeginFrame`, opens the shared NVRHI command list, and initializes lazy render passes.
- `idRenderBackend::GL_EndFrame` closes the command list, calls `DeviceManager::EndFrame`, submits with `executeCommandList`, then advances the TAA feedback/jitter frame.
- `idRenderBackend::GL_BlockingSwapBuffers` calls `deviceManager->Present`, runs NVRHI garbage collection, and closes render-log timing.
- `neo/sys/DeviceManager_DX12.cpp:DeviceManager_DX12::Present` performs DXGI presentation with configured sync/tearing flags and frame-latency synchronization.

## Resource inventory

All listed images use `renderSystem->GetWidth()/GetHeight()` unless noted. They are owned by `idImageManager`, bound into global NVRHI framebuffers, and reloaded by `Framebuffer::ReloadImages` during framebuffer recreation.

| Semantic | Image / creation site | NVRHI format and samples | Producer / consumer | Finding |
|---|---|---|---|---|
| Scene color | `_currentRenderHDR`; `neo/renderer/Image_intrinsic.cpp:R_HDR_RGBA16FImage_ResNative_Multisampled` | `RGBA16_FLOAT`; current MSAA sample count; UAV only at 1x | Main 3D scene -> motion mask, TAA or tone map | Best pre-tonemap linear/HDR candidate. Alpha is repurposed as a TAA exclusion mask late in the frame. |
| Post-tonemap color | `_currentRenderLDR` / `ldrImage`; `R_LdrNativeImage` | Capture: `R8G8B8A8_UNORM`, 1280x720, 1x | Tone map -> scene post-processing -> GUI -> final blits | Best final-LDR HUD-free boundary is after scene post-processing and before the GUI `Standard Shader Stage`. |
| Depth/stencil | `_currentDepth`; `R_DepthImage` | Capture: `D24_UNORM_S8_UINT`, 1280x720, 1x | Depth prepass -> Hi-Z/SSAO, lighting, motion reconstruction, tone map/post, GUI | Conventional Z: cleared to 1.0 and opaque depth uses `LessOrEqual`. Projection/window Z is `[0,1]`, with near near 0 and far approaching 0.999. |
| Motion vectors | `_taaMotionVectors`; `R_HDR_RG16FImage_ResNative` | `RG16_FLOAT`, 1x | `DrawMotionVectors` -> TAA compute | Camera-only current-to-previous displacement in **pixels**. No object/skinned velocity. |
| TAA resolved | `_taaResolved` | `RGBA16_FLOAT`, 1x, UAV | TAA compute -> tone map | Current resolved HDR output. |
| TAA history | `_taaFeedback1`, `_taaFeedback2` | `RGBA16_FLOAT`, 1x, UAV | TAA ping-pong | Swapped every backend frame by `TemporalAntiAliasingPass::AdvanceFrame`. |
| Exposure | `TonemapPass::exposureBuffer` | one `R32_UINT` buffer storing float bits | histogram/exposure compute -> tone-map pixel shader | Adapted luminance is GPU-resident and currently has no engine-facing neutral exposure value. |
| Geometry helper | `_gbuffer` normals/roughness + `_csDepth*` Hi-Z | renderer-specific | Ambient/SSAO/SSR | Useful diagnostics, not yet a complete neural-input contract. |

The swapchain format defaults to `RGBA8_UNORM` in `neo/sys/DeviceManager.h`; no active HDR display/output path was observed in the DX12 device manager.

## Measured temporal conventions

### Jitter

- `neo/renderer/RenderSystem_init.cpp:r_useTemporalAA` defaults to 1, but `R_UseTemporalAA` additionally requires a TAA anti-aliasing mode and normal Doom render mode.
- `r_taaJitter` defaults to 1, the eight-sample MSAA-pattern sequence in `neo/renderer/Passes/TemporalAntiAliasingPass.cpp:GetCurrentPixelOffset`.
- `neo/renderer/GLMatrix.cpp:R_SetupProjectionMatrix` applies pixel jitter as `xoffset = -2*jitterX/width`, `yoffset = -2*jitterY/height` to projection entries `[2][0]` and `[2][1]`.
- `R_RenderView` stores both jittered `worldSpace.mvp` and `worldSpace.unjitteredMVP`. The existing camera reprojection uses the unjittered matrix; the TAA pass separately receives the current pixel offset.

### Motion vectors

- `neo/renderer/RenderBackend.cpp:idRenderBackend::DrawMotionVectors` computes `previousUnjitteredMVP * inverse(currentUnjitteredMVP)` and updates `prevMVP`.
- `neo/shaders/builtin/post/motionBlur.ps.hlsl` reconstructs current NDC from screen UV and depth, transforms it to the previous clip position, maps prior Y into top-left texture coordinates, and writes `previousPixelPosition - currentSVPosition`.
- Convention: RG pixels, current -> previous; screen X right positive, screen Y down positive after the shader's NDC-to-texture Y flip.
- The pass draws a fullscreen vector field derived from depth and camera matrices only. It stores no prior `viewEntity_t::modelMatrix`/MVP and no prior MD5 joint buffer, so moving rigid objects and animated/skinned geometry receive incorrect background/camera reprojection.
- Weapon-depth-hack, `skipMotionBlur`, and subview surfaces are written as alpha zero in scene HDR and rejected by the motion-vector shader. Translucent members of that exclusion group are skipped, leaving transparency behavior incomplete.
- RenderDoc stationary frame 1487 showed only `_taaMotionVectors` clear -> barrier -> TAA read and a zero field, matching the `cameraMoved == false` path.
- RenderDoc forward-motion frame 1469 showed a nonzero signed field at `-8..8`: left-side X was positive, right-side X negative, upper Y positive, and lower Y negative. The field converged toward the vanishing point, confirming the shader-derived current-pixel -> previous-pixel sign convention. Weapon/character silhouettes also made the current exclusion behavior visible.

### History and reset state

- `prevViewsValid` is initialized false in `idRenderBackend::Init` and becomes true after the first `TemporalAAPass`.
- No other false assignment was found. `Framebuffer::ResizeFramebuffers` calls `backEnd.ClearCaches`, which recreates the TAA pass, but `ClearCaches` does not invalidate `prevViewsValid` or reset `prevMVP`.
- No proven resets were found for map load, new/load game, teleport, camera cut, resolution change, large FOV change, or device/framebuffer recreation.
- This is a correctness gap for both existing TAA and any future temporal/neural integration. Reset triggers must be wired and tested explicitly rather than inferred from resource recreation.

### Exposure

- `r_exposure` defaults to 0.5 and tone mapping uses `exp2(r_exposure)` as an exposure scale.
- `TonemapPass::SimpleRender` always clears/builds the histogram, computes adapted luminance into `exposureBuffer`, and renders using that value.
- Although `r_hdrAutoExposure` defaults off and its help says fixed exposure should be used, the observed modern `TonemapPass` path does not gate histogram/exposure compute on that cvar; the cvar is used elsewhere for bloom threshold selection. This mismatch must be resolved by a diagnostic readback/capture before defining the neutral exposure contract.

## Native D3D12 boundary

- `neo/sys/DeviceManager_DX12.cpp` owns `ID3D12Device`, graphics/compute/copy queues, and the DXGI swapchain. It creates NVRHI from a `nvrhi::d3d12::DeviceDesc` containing those native objects.
- NVRHI exposes the required native escape hatches:
  - `IDevice::getNativeObject(D3D12_Device)` -> `ID3D12Device`.
  - `IDevice::getNativeObject(D3D12_CommandQueue)` -> graphics queue.
  - `ICommandList::getNativeObject(D3D12_GraphicsCommandList)` -> active command list while open.
  - `ITexture::getNativeObject(D3D12_Resource)` -> `ID3D12Resource`.
- Evidence is in `neo/extern/nvrhi/src/d3d12/d3d12-device.cpp`, `d3d12-commandlist.cpp`, and `d3d12-texture.cpp`. The renderer already unwraps the active command list for Optick GPU contexts, so native access does not require bypassing NVRHI ownership.
- The correct future integration pattern is to keep NVRHI responsible for resource lifetime/state tracking, request explicit resource states around an isolated native evaluate call, and restore/declare states before returning to NVRHI. Exact barriers cannot be chosen until a public SDK contract is selected.

## Diagnostics and capture readiness

- `neo/renderer/RenderLog.cpp:r_logLevel` enables named NVRHI command-list markers intended for RenderDoc.
- Optick GPU initialization exists in `DeviceManager_DX12.cpp`, with GPU events around major passes. `USE_OPTICK` remains a build option/definition.
- The `screenshot` console command calls `idRenderSystemLocal::TakeScreenshot`; `R_WritePNG`, `R_WriteTGA`, and `R_WriteEXR` are available. A `renderView_t` screenshot can omit HUD, but ordinary screenshots are final-output checks rather than arbitrary GPU-resource capture.
- RenderDoc 1.46 was installed locally through the verified Winget package after the baseline run. It is a system diagnostic tool only and is not copied into or tracked by the repository.
- Nsight Graphics was not installed. NVIDIA documents current Nsight Graphics support for RTX 50-series and D3D12, so it remains a fallback for driver-specific debugging/profiling.

### RenderDoc baseline evidence

- The first F12 capture was intentionally retained as failed evidence: the key also invoked RBDOOM's screenshot path, producing a valid container with only buffer unmaps and `Present`.
- Using Print Screen avoided the conflict and produced complete captures with RenderDoc reporting no replay problems.
- Stationary frame 1487: ignored local file `captures/neural/renderdoc-baseline-pass2/baseline_frame1487.rdc`, 430,744,078 bytes, SHA-256 `4BE1C051078CBB08C974F622566C864894EC32DC452CC0263C6AB714CC3614B4`.
- Forward-motion frame 1469: ignored local file `captures/neural/renderdoc-motion/lateral_frame1469.rdc`, 435,818,501 bytes, SHA-256 `D734ADF641C71EABC1499D1224372040048EC8AE001BA70A0CA1AB3BBB397BA8`.
- Frame 1487 event order: `Render_MotionVectors` EID 8074-8080; `Render_TemporalAA` 8085-8092; `Render_ToneMapPass` 8097-8126; first swapchain blit 8130-8142; `Render_PostProcessing` 8146-8180; `Render_DrawViewGUI` 8185-8308.
- Captured resources: `_currentRenderHDR` is 1280x720 `R16G16B16A16_FLOAT`; `_currentDepth` is single-sample `D24_UNORM_S8_UINT`; `_currentRenderLDR` is single-sample `R8G8B8A8_UNORM`; `_taaMotionVectors` is single-sample `R16G16_FLOAT`. `_taaFeedback1`, `_taaFeedback2`, and `_taaResolved` are present and active in the TAA sequence.

## Candidate insertion points

1. **HUD-free LDR diagnostic/copy:** at the backend command boundary after scene `Render_PostProcessing` completes and before `Render_DrawViewGUI` begins. A simpler earlier diagnostic immediately after `TonemapPass::SimpleRender` is still useful, but it omits scene post-processing observed in the final LDR path.
2. **Pre-tonemap temporal evaluate point:** after `DrawMotionVectors` and before/at `TemporalAAPass`, using `_currentRenderHDR`, `_currentDepth`, `_taaMotionVectors`, unjittered/jitter data, reset state, and future masks. This is only a candidate until inputs are validated.
3. **Native D3D12 call boundary:** inside the already-open backend NVRHI command list at the chosen evaluate point, below an engine-facing neutral interface and behind an OFF-by-default build option.
4. **History reset hook:** a renderer API/event consumed at the start of the main 3D view, with producers at proven game/map/camera/resolution discontinuities.

## Top risks and unanswered questions

1. Existing vectors are camera-only; rigid and skinned motion must be implemented incrementally.
2. No complete history reset lifecycle exists.
3. The viewmodel is temporally excluded through HDR alpha rather than explicitly separated; the intended neural composition policy is unresolved.
4. Translucency, smoke, muzzle flashes, glass, emissive animation, and subviews lack an explicit reactive/transparency mask contract.
5. The GPU exposure buffer does not yet expose a verified CPU/API value, and `r_hdrAutoExposure` behavior conflicts with the active tone-map path.
6. `_ldr` is HUD-free only at a moment in the command stream, not as a durable separate texture.
7. MSAA depth/HDR resources need explicit resolve policy for any SDK input; this captured TAA baseline is confirmed single-sample.
8. Debug-runtime DLL dependencies make `RelWithDebInfo` unsuitable for distribution without a separate packaging decision.
9. No Streamline/DLSS SDK version, public API contract, redistribution license, or dependency mechanism has been selected. External feeder/RenoDX remains manual local validation only.

## Recommended next narrow code task

Implement an OFF-by-default **diagnostic output-separation scaffold** that can preserve or capture `_ldr` after scene post-processing and before GUI rendering. It should:

- add one renderer cvar/debug mode following existing patterns;
- use NVRHI resources and markers;
- leave the disabled path pixel-equivalent;
- identify scene-only versus final-with-UI output in RenderDoc;
- record format, dimensions, resource states, and command ordering;
- avoid SDK/vendor code.

The stationary and forward-motion RenderDoc captures above satisfy the Phase 2 capture gate. TAA execution and single-sample resources are proven; a console cvar dump remains useful metadata but no longer blocks the narrow Phase 3 diagnostic task.
