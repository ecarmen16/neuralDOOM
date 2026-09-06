# Unattended builds, rendering checks, and ultrawide HUD

Run from the repository root in PowerShell. Local BFG data is required for gameplay checks. No retail assets or optional runtime downloads are performed by these tests.

## Build and identify the exact executable

```powershell
.\tools\neural-rendering\Configure-RBDOOM-DX12.ps1
.\tools\neural-rendering\Build-RBDOOM.ps1 -Configuration RelWithDebInfo
.\tools\neural-rendering\Test-NeuralBuildIdentity.ps1
```

CMake emits `build/neuraldoom-artifact-RelWithDebInfo.txt` with the exact target path. The build helper writes `build/neuraldoom-build-RelWithDebInfo.json` containing the executable hash, configuration, feature flags, commit, and dirty-worktree flag. A failed build invalidates its previous success manifest. An up-to-date incremental build is valid; a missing target is an error, with no fallback to Release or a staged executable.

Pass `-BuildDirectory build-streamline` to configure/build/run helpers to use the existing locally provisioned SDK configuration. This argument does not install or enable the SDK; the existing CMake cache must already select it. Default build output is not copied over the root launcher executable. `-StageExecutable` is an explicit build-helper option.

## Bounded gameplay checks

```powershell
.\tools\neural-rendering\Test-NeuralDoom-Smoke.ps1 -Profile Native
.\tools\neural-rendering\Test-NeuralDoom-Smoke.ps1 -Profile Validate -Width 2560 -Height 720 -HudMaxAspect 1.777778 -HudScale 1.15
.\tools\neural-rendering\Test-NeuralDoom-Smoke.ps1 -BuildDirectory build-streamline -Profile DLAA -Width 2560 -Height 720 -HudMaxAspect 1.777778
```

Each run gets a unique ignored `captures/neural/smoke-*` directory with disposable configs/saves, `base/smoke.log`, before/after PNGs, and `result.json`. It checks exact build identity, a gameplay script completion marker, primary-view frame progress, a manual history-reset epoch change, requested-backend evaluation/presentation, and PNG output dimensions. The scene is `game/mars_city2`; warm-up is 180 frames, followed by a configurable measurement interval and reset. Only the process started by that invocation is terminated on timeout.

PASS means these automated checks passed. It does not certify absence of ghosting, clipping in every HUD state, or subjective image quality. SKIP is reserved for known missing prerequisites (SDK-OFF, absent staged SDK DLLs, missing local map data). Runtime feature failures remain FAIL so unexpected GPU/SDK regressions are visible. The sandbox may deny SDK/driver access even when native DX12 runs; record both attempts rather than silently treating failed DLAA as a pass.

Windows startup arguments have a 1024-byte engine limit. Scenario settings live in the generated cfg, and the runner rejects an overlong command line. Screenshots now use `fs_savepath` on Windows/Linux as they already did on macOS; normal user screenshots move to the configured save folder's `base/screenshots` directory.

## HUD controls

```text
swf_hudMaxAspect 1.777778
swf_hudScale 1.15
```

These archived cvars apply to the gameplay HUD only. The first centers ordinary HUD edge anchors within a maximum 16:9 width on wider displays; it never expands beyond the display. A positive aspect below 1 is treated as 1. The second uniformly scales HUD artwork from 0.5 to 1.5. At 5120x1440, a 16:9 safe width spans the middle 2560 pixels. The underlying world continues to use the entire display.

Defaults are `swf_hudMaxAspect 0` (full width) and `swf_hudScale 1` (original size). Controls are live and do not change world-camera or weapon FOV. Menus, PDA/world GUIs, absolute-edge anchors, and full-screen overlay bounds retain their existing placement. HUD scaling also scales centered HUD elements, including the crosshair. The SWF mouse-coordinate conversion uses the last rendered HUD scale. Split-screen render calls retain their existing layout.

The smoke runner's HUD settings are disposable and do not change the user's saved preferences. In-game visual controls remain opt-in pending broader interaction, notification, and motion review.
