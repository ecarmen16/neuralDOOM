# Implementation notes

Append dated entries. Do not replace prior evidence.

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
- `_currentRenderHDR` is the pre-tonemap scene candidate. `_currentRenderLDR` is HUD-free only immediately after the 3D tone-map pass; later GUI commands mutate it.
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
