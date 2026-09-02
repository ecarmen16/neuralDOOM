# Implementation notes

Append dated entries. Do not replace prior evidence.

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
