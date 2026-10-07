# Test plan

## 1. Principles

Temporal rendering defects are easiest to hide in still screenshots. Every important input must be checked in motion, in a debug visualization, and in a final reconstructed output. Claims require exact build, cvar, resolution, driver, and scene information.

## 2. Baseline matrix

Record:

- upstream commit and local branch;
- build configuration and CMake options;
- Windows build and GPU driver;
- GPU model;
- executable SHA-256;
- output resolution and HDR state;
- `r_graphicsAPI` and AA settings;
- map/save and reproducible camera action;
- average and representative frame time, not FPS alone.

## 3. Functional scenarios

| ID | Scenario | Expected evidence |
|---|---|---|
| T01 | Static camera/static world | Motion vectors are zero or the documented jitter-only value; no temporal crawl. |
| T02 | Camera yaw | Smooth directionally correct vectors across static geometry. |
| T03 | Camera lateral translation | Parallax magnitude changes correctly with depth. |
| T04 | Moving door or lift | Object velocity differs from camera/background velocity. |
| T05 | Rigid physics object | Stable object-local history without trails after rest. |
| T06 | Animated MD5 monster, static camera | Character velocity exists while background remains static. |
| T07 | Animated monster plus moving camera | Camera and skin motion combine correctly. |
| T08 | Weapon bob and recoil | Chosen viewmodel policy avoids smearing and depth discontinuities. |
| T09 | Muzzle flash/projectile | Reactive policy limits history contamination. |
| T10 | Smoke/flame/particles | No long-lived trails; masks classify unstable pixels. |
| T11 | Glass/transparency | Composition and transparency mask are correct. |
| T12 | Animated emissive/material stage | Bright animation does not poison history. |
| T13 | In-world GUI/video surface | Deliberate scene-content behavior is documented. |
| T14 | HUD/menu | UI is composed sharply outside the reconstructed scene. |
| T15 | Map load/save load | History resets; no prior-scene ghost. |
| T16 | Camera cut/cinematic transition | History resets on the correct frame. |
| T17 | Resolution/HDR change | Resources recreate safely and history resets. |
| T18 | Feature disabled/unavailable | Baseline rendering remains valid. |

## 4. Debug-view acceptance

### Depth

- Near/far behavior matches the documented normal or reversed-Z convention.
- World depth excludes or deliberately includes the viewmodel.
- Resize and MSAA/resolve behavior are understood.

### Motion vectors

Use a signed visualization with a legend and a numeric inspection path. Verify:

- zero point;
- positive X/Y directions;
- unit conversion;
- jitter handling;
- clamping behavior;
- invalid/disoccluded encoding.

### Reactive/transparency masks

Display each mask independently and overlaid on color. Check that masks do not indiscriminately cover the entire frame, which would destroy temporal reuse.

### HUD-free color

Pixel-diff the normal scene before UI against the debug-presented HUD-free texture, accounting only for deliberate stage differences.

## 5. Regression gates

For each focused change:

```powershell
.\tools\neural-rendering\Configure-RBDOOM-DX12.ps1
.\tools\neural-rendering\Build-RBDOOM.ps1 -Configuration RelWithDebInfo

git diff --check
git status --short
```

Include the relevant runtime scenario, results and limitations in the pull request.

### Pull-request checks

The `Renderer validation` workflow provides two stable checks on every pull request:

- **Renderer offline checks** runs command-wrapper, public-source audit, release-uploader, build-identity and declared-submodule fixtures. It requires no SDK, retail data or GPU.
- **Renderer compile checks** runs the CPU contracts in a VS2022 x64 compiler environment, then sequential DX12 `RelWithDebInfo` builds with RT/Streamline both OFF, RT ON/Streamline OFF, and RT/Streamline both ON. After each RT build it inspects compiled reflection and player-shadow shader contracts with that build's DXC and runs reflection-material/cache/coverage fixtures, including fresh shader compilation for defined control-flow values. Shared `base/renderprogs2` outputs are consumed before the next build. The compile check records a successful skip for changes outside renderer/build/workflow/wrapper paths.

After this workflow has been merged and both checks have run, repository administrators can require those exact check names in branch protection. CI does not replace the latest manual PR approval or the renderer playtest required by `AGENTS.md`.

Local equivalents from a Windows checkout:

```powershell
.\tools\neural-rendering\Test-RendererContracts.ps1 -Suite Offline
.\tools\neural-rendering\Test-RendererContracts.ps1 -Suite CPU
.\tools\neural-rendering\Test-RendererContracts.ps1 -Suite Shaders -Dxc <build-DXC-path>
.\tools\neural-rendering\Build-RendererValidation.ps1 -RepoRoot <neutral-source-path>
```

The offline suite's final repository audit requires a clean checkout; individual fixture scripts also run while editing. The CPU and shader suites initialize the installed VS2022 compiler environment themselves. The shader suite requires the compiled DXIL files in the specified checkout and its build compiler. The build helper obtains only the existing hash-verified official ISPC and Streamline pins and leaves all outputs ignored. It does not package, upload or launch the engine. Passing these checks establishes source/CPU/shader contracts and compilation, not GPU correctness, visual quality or gameplay acceptance.

## 6. Performance capture

Record CPU and GPU frame times separately when tools permit. At minimum capture:

- baseline renderer;
- debug resources allocated but feature disabled;
- temporal input generation;
- native DLAA/DLSS evaluation;
- Neural Rendering experiment when applicable.

Use a stable resolution and scene. Report median plus a high percentile or visible frame-time distribution; do not report one instantaneous FPS number as a conclusion.

## 7. Release gate

No public artifact until:

- legal/dependency checklist is complete;
- default no-SDK build passes;
- unsupported hardware path passes;
- game data and local runtimes are absent from the archive;
- source and notices satisfy applicable licenses;
- known visual regressions are documented;
- official versus experimental functionality is labeled accurately.
