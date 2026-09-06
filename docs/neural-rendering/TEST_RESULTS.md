# Test results

## 2026-09-06 / modernization foundation working tree

Base `76ff35b5`, branch `codex/modernization-foundation`. Automated checks used disposable `game/mars_city2` runs and local owned BFG data. The experimental ReShade/NR compatibility layer was disabled. Results prove the checks listed here, not an NR aesthetic comparison or monitor HDR capability.

| Check | Result | Evidence |
|---|---|---|
| DX12 SDK-OFF configure/build | PASS | `Configure-RBDOOM-DX12.ps1`; `Build-RBDOOM.ps1 -Configuration RelWithDebInfo -Parallel 8`; ignored `captures/neural/modernization-build-off.log` |
| DX12 SDK-ON configure/build | PASS | Same helpers with `-BuildDirectory build-streamline`; existing pinned SDK cache retained; `captures/neural/modernization-build-on.log` |
| Exact artifact and failure-path fixtures | PASS | `Test-NeuralBuildIdentity.ps1`: custom target/directory, missing output despite stale alternatives, missing configuration, successful compiler with absent target, stale success-manifest removal |
| PowerShell parsing | PASS | Parser invoked inside the test script with terminating errors; all helper scripts parsed |
| Native 1280x720 / default HUD | PASS | `smoke-20260906-110603-1c1b7b8d`: exit 0, 64 primary-view frames between probes, reset epoch advanced, both PNG dimensions checked |
| Null validation 2560x720 / centered HUD at 1.15 scale | PASS | `smoke-20260906-110625-9b80130a`: 124 primary-view frames, 297 evaluated / 0 rejected, epoch 4 to 5, captures |
| DLAA 2560x720 / centered HUD | PASS with normal driver access | `smoke-20260906-110951-68fca31c`: 297 evaluated / 297 presented / 0 rejected; 124 primary-view frames and reset/capture checks |
| Native 2560x720 / original full-width HUD | PASS | `smoke-20260906-111057-b094f1ec`: 64 frames, exit/reset/capture checks; inspected screenshot shows original edge placement |
| Native 1680x720 / centered 16:9 HUD | PASS | `smoke-20260906-111120-9631580d`: 64 frames, exit/reset/capture checks; screenshot inspected |
| DLAA requested on SDK-OFF build | SKIP as intended | `smoke-20260906-111142-a336f3f3`: explicit missing-SDK result, no process launched |

Run directories above are under ignored `captures/neural/`. Build identities: SDK-OFF SHA-256 `254E2D567BAF2955F0D95F549EC03298A182189FA363FBBF5CE332A626D67BF6`; SDK-ON `BD7A34163B0E953DE0EB49F337316208D0A688CC8A635A3DE72862836469FE6F`. JSON manifests record the dirty development state and exact executable. No runtime binaries or game data are tracked.

### Failures encountered and corrected or characterized

- Sandbox MSBuild failed first on its temporary directory and then Windows SDK discovery permissions. Normal Windows SDK access produced successful builds.
- An early build/run overlap locked the executable at link time; the test-owned process exited and the sequential rebuild passed. Do not build and run the same target simultaneously.
- The first runner exceeded Win32's 1024-byte command-line storage and lost its trailing scenario invocation; it timed out and cleaned up its process. Runtime settings were moved into the generated cfg and a byte-length guard was added.
- The next run completed gameplay but failed capture validation because Windows screenshots wrote into `fs_basepath`. `R_ReadPixelsRGB8` now uses `fs_savepath` consistently; subsequent captures stayed in each isolated run. Early diagnostic captures remain ignored local artifacts.
- Sandboxed SDK-ON run `smoke-20260906-110845-35674ded` reported `eErrorFeatureMissing`, 297 rejected evaluations, and native fallback, so the runner correctly failed the DLAA expectation. The same executable passed with normal driver access. This was not hidden as a successful DLAA run.

### Visual inspection and limits

Inspected 32:9 centered/scaled, 32:9 original full-width, and 21:9 centered captures. Health/ammo placement moves inward as intended while the world remains full-width. These are different wall-clock animation samples, not pixel-equivalence proofs. No user playtest was requested.

Upstream content/cinematic-image and unknown reliable-message warnings appeared in smoke logs. No fatal error was observed in passing runs; warnings were not treated as proof of a warning-free engine.

Not yet covered: all HUD notifications and interactive states, PDA/menu image comparisons, split-screen/VR, wide FOV transitions, full motion/ghosting matrix, invalid temporal-resource injection tests, GPU timing thresholds, Vulkan builds, actual 5120x1440 capture, live resize, native display HDR, and NR bridge gameplay on this revision. New HUD controls stay opt-in. No new geometry, lighting, or HDR-output effect is claimed by this batch.

Final source audit and diff review are recorded with the checkpoint; see `UNATTENDED_WORKFLOW.md` for commands and screenshot-location changes.

## 2026-09-03 / ND3-520 / guided local assembly

- Guided setup dry-run: PASS. PowerShell 5 executed the updated setup noninteractively against the established Steam BFG installation; Robocopy found 384/6.932 GB source files and copied zero because the local install was current.
- Runtime inventory: PASS. The staged `neuralDoom.exe`, Streamline/DLSS runtime, embedded ReShade runtime, add-on, and `nvngx_dlssnr.dll` were detected; the proxy `dxgi.dll` remained absent as expected for embedded startup.
- D3HDP installed-state handling: PASS. The existing ignored `mod_D3HDP_Lite/` was retained. The prior local archive remains recognized by exact size and SHA-256; the current ModDB release is pinned to the canonical page's reported size and MD5 for the clean-install download test.
- Public-source audit: PASS with `-AllowDirty`. All 2,445 tracked files were checked; no retail resource/capture, local runtime payload, cache/mod directory, or concrete local machine path was tracked.
- Pending: exercise a fresh 2 GB ModDB download/mirror redirect and a fresh NR file/URL copy in a disposable clean install. Neither path was forced against the user's working installation during this validation.

## 2026-09-03 / ND3-350 / engine-owned compatibility startup

- `RelWithDebInfo`, Streamline-enabled: PASS. Reconfigured `build-streamline` after adding the renderer source and built/staged `neuralDoom.exe` successfully (19,845,120 bytes; SHA-256 `FE2944D2B4EC0536FF846B1BB47A86FDDFC740864E636D128540C34D9FB07DFD`).
- `RelWithDebInfo`, SDK-OFF: PASS. Reconfigured `build` and built the default executable successfully; the compatibility loader has no link-time ReShade dependency and defaults disabled.
- Reversible local mode switch: PASS. The helper moved the ignored `dxgi.dll` to `neuraldoom-reshade64.dll` and left no proxy DLL beside the executable.
- Embedded startup probe: PASS. `ReShade.log` identifies ReShade 6.8.0.2155 as loaded from `neuraldoom-reshade64.dll`; DLSS5 add-on version `0.2026.828.2110` registered with API 18; the local NR runtime was preloaded at device init; a ReShade runtime was created on the RTX 5090 at 1280x720.
- Gameplay/visual parity with the earlier feature-18 pass: PASS. The user launched the embedded NR + D3HDP profile and confirmed that the NR path and F6 behavior still work in gameplay.

## 2026-09-02 / working tree / neuralDoom setup and identity

- Tester/machine label: local Windows development machine; automated setup/build/smoke validation.
- Branch and base commit: `feature/neural-rendering-spike`, `ca0eeec5` plus the documented working-tree changes.
- Build configuration: SDK-OFF and Streamline-enabled `RelWithDebInfo`, VS2022 x64.
- CMake options: DX12 only; `APP_NAME=neuralDoom`; Streamline optional and OFF by default.
- Game data: user-owned Doom 3 BFG installation at the established local Steam path; 6.9 GB source `base` scan.

| Test | Result | Evidence / artifact path | Notes |
|---|---|---|---|
| Exact downstream target | PASS | `build/RelWithDebInfo/neuralDoom.exe`; `build-streamline/RelWithDebInfo/neuralDoom.exe` | Both configurations compiled successfully; only established upstream `StrCmp*` macro warnings observed. |
| Unified setup, retail data | PASS | `tools/neural-rendering/Setup-NeuralDoom.ps1` console run | Located 384 source files; existing local destination was current; no copy failures. |
| D3HDP validation | PASS | user archive plus ignored `mod_D3HDP_Lite/` | Verified pinned SHA-256 before recognizing the already-installed isolated mod. |
| Runtime inventory | PASS | setup console run | Engine, Streamline, NGX DLSS, ReShade proxy, RenoDX add-on, and local NR runtime all detected without being copied or tracked. |
| Feature-off smoke | PASS | staged ignored `neuralDoom.exe` | DX12 launch with `r_streamlineEnable 0` and `+quit` exited code 0. |
| Staged identity | PASS | ignored `neuralDoom.exe` | 19,838,464 bytes; SHA-256 `74BF93FF000AA42F75C91BB63BD7968BD68E9C8A1CC34E6086B1D77C1757EAEA`. |

### Regressions

- None observed in the automated feature-off smoke. Full visual D3HDP/NR quality validation remains the user's active manual test.

### Conclusion

- ND3-500 and ND3-510 pass. Direct downloads remain gated on the ND3-520 component manifest and license/source review.

## 2026-09-02 / ND3-340 / local RenoDX DLSSNR interception

- Local-only validation layer: ReShade 6.8.0.2155 and RenoDX DLSS5 Generic v4.1.5, loaded from ignored files beside the custom executable. No ReShade, RenoDX, NVIDIA NR runtime, retail data, or captured output is tracked.
- Engine launch: DX12, Streamline enabled with experimental application ID `0`, `r_neuralBackend 2`, `r_screenFraction 100`, Doom render mode, and native TAA routing enabled.
- Scene/output: saved gameplay at 5120x1440 native input and output.

| Test | Result | Evidence |
|---|---|---|
| NGX interception | PASS | Local `ReShade.log` reports the engine DLSS/DLAA feature create and evaluate were intercepted. |
| Experimental DLSSNR evaluation | PASS | Feature 18 initialized and evaluated successfully at 5120x1440 with full-resolution guides; the add-on reported successful frames and result `0x00000001 (ok)`. |
| Runtime toggle | PASS | The local log records repeated F6 off/on transitions followed by successful feature recreation. |
| Visible neural output | PASS | User confirmed the corrected launch produced a visibly new model-generated image. Previous near-inert runs are attributed to an inconsistent launch state, not absence of model execution. |

Compatibility is proven for private local experimentation. Visual-quality tuning and a controlled screenshot matrix remain manual follow-up work; this result does not approve redistribution of the experimental runtime or add-on.

## 2026-09-02 / ND3-330 preliminary / DLSS Quality extent smoke test

| Test | Result | Evidence |
|---|---|---|
| SDK-OFF and SDK-ON builds | PASS | Both VS2022 x64 DX12 `RelWithDebInfo` trees linked after adding mode `3` and view-extent reporting. |
| 67%-to-native evaluation | PASS | `neuralBackendStatus`: 153 evaluated, 153 presented, 0 rejected; render 857x482, output 1280x720, last `DLSS Quality evaluated`. |
| Project-priority review | DEFERRED | The RTX 5090 does not need reconstruction for Doom 3 performance. Quality mode remains an infrastructure diagnostic; the planned NR path should normally retain 100% source resolution. |

## 2026-09-02 / ND3-320 / native-resolution Streamline DLAA

- Build: VS2022 x64 `RelWithDebInfo`, DX12; both SDK-OFF and ignored official Streamline v2.12.0 SDK-ON configurations.
- Runtime: RTX 5090, custom-engine application ID `0`, `r_streamlineEnable 1`, `r_neuralBackend 2`, 1280x720 native-resolution DLAA Preset K.
- Scene: disposable `devmap game/mars_city2`; engine log stored in the local save path and not tracked.

| Test | Result | Evidence |
|---|---|---|
| Default SDK-OFF regression build | PASS | `build/RelWithDebInfo/RBDoom3BFG.exe` linked without Streamline headers, libraries, or runtime. |
| SDK-ON build and staging | PASS | `build-streamline/RelWithDebInfo/RBDoom3BFG.exe` linked and staged only ignored local SDK DLLs. |
| Feature/device/backend initialization | PASS | Streamline initialized with experimental custom-engine identity, accepted D3D12, reported DLSS supported, and initialized the DLAA backend. |
| Native DLAA evaluation | PASS | `neuralBackendStatus`: 597 evaluated, 597 presented, 0 rejected, epoch 4, render/output 1280x720, last result `DLAA evaluated`. |
| Ordered shutdown | PASS | Scripted map run processed `+quit` and shut down the renderer/game without a fatal error. |
| Saved-game image-quality A/B | PASS / subtle | User found it difficult to see a difference from native TAA and reported no visible regression. This validates presentation but does not establish a compelling standalone visual gain. |

No Streamline or NVIDIA binary is tracked. Public binary distribution remains blocked pending qualified license review.

## 2026-09-01 / 71392b90 + ND3-320 worktree / Streamline core lifecycle

- SDK build: `USE_STREAMLINE=ON`, official local Streamline `v2.12.0`.
- Runtime controls: `r_streamlineEnable 1`, `r_streamlineApplicationId 0`, DX12, windowed, experimental custom-engine identity.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.

| Test | Result | Evidence |
|---|---|---|
| Default SDK-OFF build | PASS | Established configure/build helper compiled stubs and linked `RelWithDebInfo` without an SDK dependency. |
| SDK-ON build/runtime staging | PASS | Isolated build linked and copied the four required local runtime DLLs beside the ignored executable. |
| Early core initialization | PASS | Ignored `captures/neural/streamline-smoke/base/streamline_core.log`; the original probe initialized Streamline core before DX12 creation. |
| Native D3D12 device handoff | PASS | Same log: RTX 5090 device created, followed by `Streamline accepted the native D3D12 device`. |
| Startup fallback | PASS | Hidden process remained alive after ten seconds; this first lifecycle probe did not yet request DLSS. |
| Experimental DLSS feature request, application ID 0 | PASS | Ignored `captures/neural/streamline-dlss-probe/base/streamline_dlss_probe.log`: custom-engine identity initialized, native D3D12 device accepted, and `DLSS supported`. |
| Ordered shutdown | PASS | A 120-frame scripted run processed engine `+quit` and exited normally with code 0 after the Streamline-enabled initialization path. |

The reversible core lifecycle and local DLSS feature load/support probe are validated with application ID `0`. An NVIDIA-issued identity is deferred to any future supported distribution and does not gate private implementation. Native presentation remains active until resource tagging and evaluation are integrated.

## 2026-09-01 / ND3-300 + ND3-310 worktree / official SDK gate

- Official SDK: NVIDIA Streamline `v2.12.0`, kept under ignored local storage; release archive SHA-256 matched the vendor-published digest.
- Default build: `USE_STREAMLINE=OFF`, established VS2022 x64 DX12 configuration.
- SDK build: `USE_STREAMLINE=ON`, isolated ignored `build-streamline` tree, local `STREAMLINE_SDK_PATH`.

| Test | Result | Evidence |
|---|---|---|
| Default/OFF configure and build | PASS | Established configure helper and `RelWithDebInfo` build completed; no Streamline path required. |
| SDK/ON configure | PASS | CMake found the official SDK headers and `lib/x64/sl.interposer.lib` only when explicitly supplied. |
| SDK/ON build and link | PASS | `build-streamline/RelWithDebInfo/RBDoom3BFG.exe`, 19,822,080 bytes; SHA-256 `438ADEEA28C02512029026CF3DC40CBA8E34B97DC39AF0067BF926536A0568F4`. |
| Repository isolation | PASS | `local-proprietary/` and `build-streamline/` remain ignored; only CMake and documentation changes are tracked. |
| Neutral interface visible regression | PASS | User-visible saved gameplay reported 1,076 evaluated frames, 0 rejected, matching 1725x985 render/output dimensions, and intact world/weapon/HUD presentation. |

ND3-300 and ND3-310 are `DONE`. This proves an optional, reversible build boundary; no Streamline runtime calls or redistributable package are enabled by this checkpoint.

## 2026-09-01 / b4d2225a + ND3-280 worktree / neutral backend interface

- Build: `RelWithDebInfo`, VS2022 x64, DX12 only; pass.
- Default path: `r_neuralBackend 0`; ten-second staged startup remained alive.
- Validator path: `r_neuralBackend 1`, with legacy `r_taaMotionVectors 0` to prove forced input generation.

| Test | Result | Evidence |
|---|---|---|
| Contract compile/lifecycle | PASS | Full configure/build included `NeuralTemporal.cpp`; staged executable hash `71ECE524E25533B168BB75AA0D8CFA262F7182DD5167A62D6BFA1F3087E9F886`. |
| Disabled fallback | PASS | Default mode remained alive for ten seconds; no vendor dependency or GPU evaluation enabled. User-visible validator run retained normal rendering. |
| Null/debug consumption | PASS | Automated run: 177 evaluated and 0 rejected. User-visible saved gameplay: 1,076 evaluated, 0 rejected, epoch/reset epoch 4, render/output 1725x985. |
| Existing TAA fallback | PASS | Null backend always returns `false`; the existing `TemporalAAPass` executes unchanged. User confirmed normal gameplay, weapon, HUD, and objective presentation. |

ND3-280 is `DONE`. Automated and visible validation prove complete frame consumption without changing presentation.

## 2026-09-01 / e6b0fed3 + ND3-270 worktree / temporal-history lifecycle

- Tester/machine label: local Windows development machine; scripted transition tests and combined user visual check completed.
- Branch and base commit: `feature/neural-rendering-spike`, `e6b0fed3`.
- Build configuration: `RelWithDebInfo`, VS2022 x64, DX12 only.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Scene/map: disposable `devmap game/mars_city2`.
- Relevant controls: `neuralHistoryStatus`, `neuralHistoryReset`, `g_fov`, `r_screenFraction`, `setviewpos`, and `vid_restart`.

| Test | Result | Evidence | Notes |
|---|---|---|---|
| Configure/build | PASS | established configure; final build output | All shaders current; C++ linked/staged; SHA-256 `EDB8BB8641CCD35FB8078C4634813B3D11DAFC79FB03476099DE4FCE1D456E21`. |
| T15 map/save-load signal | PASS | scripted map load, user save resume, and `neuralHistoryStatus` | First tracked view consumed `initialization|level-load|framebuffer-resize`; resumed gameplay rendered normally without stale feedback. |
| Manual reset propagation | PASS | `temporal_history_sequence.log` | Epoch advanced 4 to 5; subsequent status showed the request consumed by a rendered primary view. |
| T16 camera teleport/cut | PASS | extreme disposable `setviewpos`, source review, and combined visible regression | Epoch advanced with named `camera-teleport|camera-cut`. Authored camera files now emit an exact cut bit; normal camera motion remained stable. |
| Major FOV discontinuity | PASS | `g_fov 80 -> 120`, 30 rendered frames, named status | Epoch advanced and last reason reported `fov-change`. |
| Render viewport change | PASS | `r_screenFraction 100 -> 50 -> 100` | Each changed viewport advanced the epoch after rendered-frame consumption. |
| T17 framebuffer/video restart | PASS | hidden sequence plus user-visible `vid_restart` | Resize requested a new epoch and immediately cleared backend validity. User confirmed intact rendering; status reported epoch 6, pending none, last reset `framebuffer-resize`, and a valid tracked view. |
| Portal-sky history isolation | PASS by focused review/build | `RDF_NO_TEMPORAL_HISTORY` path | Auxiliary view performs current-only resolve for tonemapping and cannot update primary MVP/feedback. |

### Regressions and limits

- No crash, early exit, or renderer error occurred in scripted map/FOV/teleport/viewport/restart sequences.
- Existing missing-envprobe and reliable-message warnings on the disposable map are unchanged and unrelated.
- User observed no crash, stale-frame flash, smear, ghost trail, or other visual regression during the combined save/FOV/restart check.

### Conclusion

The unified epoch, automated reset paths, and combined visible regression pass. ND3-270 is `DONE`.

## 2026-09-01 / 99b03cf5 + ND3-260 worktree / reactive and transparency masks

- Tester/machine label: local Windows development machine; runtime visually checked by user.
- Branch and base commit: `feature/neural-rendering-spike`, `99b03cf5`.
- Build configuration: `RelWithDebInfo`, VS2022 x64, DX12 only.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Scene/save/map: `game/mars_city2`, pistol combat with a demon worker, smoke, muzzle effects, animated screens, and mixed world materials.
- Relevant cvars: `r_neuralDebug 3` (reactive red), `r_neuralDebug 4` (transparency cyan); feature-off smoke used `r_neuralDebug 0` and `r_neuralTemporalMasks 0`.

| Test | Result | Evidence | Notes |
|---|---|---|---|
| Configure and build | PASS | configure/build output; staged executable | 768 DXIL tasks; C++ linked; SHA-256 `0C5F0FF4274C60AFAD213F0C254FCD215615D9F9BF14051CB8AF8AF449228294`. |
| T09 reactive combat effects | PASS | user manual combat observation | Red diagnostic identified muzzle/exhaust, smoke, animated screens, and other unstable work. Texture-aware sampling removed the original white particle-proxy rectangle. |
| T10 alpha/translucent coverage | PASS after correction | user manual observation and local RenderDoc captures | Cyan diagnostic initially classified broad floor/world additive and emissive stages. Restricting it to alpha/premultiplied-alpha/glass composition produced localized transparency coverage accepted by the user. |
| T11 in-world GUI/dynamic stage | PASS | user manual observation and material classification | Dynamic screens remain reactive; GUI/subview fallback uses geometry coverage when no sampleable ambient stage exists. |
| T12 overlap/coverage behavior | PASS | combat motion and smoke observation | Maximum blending preserves strongest sampled coverage without accumulating faint overlapping particles toward opaque white. |
| T13 UI separation and feature-off | PASS | diagnostic behavior plus automated startup smoke | Diagnostics intentionally overwrite GUI/console; normal mode leaves HUD/console intact. Disabled process stayed alive for ten seconds and closed normally. |
| GPU capture inspection | PASS / classifier correction | local `transparency_frame2422.rdc`, `transparency_frame2548.rdc`, `transparency_frame2742.rdc` | Per-material markers and combat captures distinguished additive/emissive reactive stages from true alpha-composed transparency. Captures are intentionally untracked. |

### Performance

- Baseline and enabled frame time: not measured.
- Disabled mode performs no mask clear or classification draw, although both native-resolution `R8` resources remain allocated.
- Enabled mode scans visible material stages and redraws classified geometry into two single-channel targets; performance tuning is deferred until the inputs have a consumer.

### Regressions and limits

- None observed in the final combat diagnostics or disabled-path startup smoke.
- Classification remains heuristic; cubemap texgens and unusual custom blends may require later targeted handling.
- The masks are generated but not yet wired into TAA or a vendor backend.

### Conclusion

ND3-260 and combined T09-T13 pass. D-008 records the independent reactive/transparency contract, and ND3-270 history-reset lifecycle is now `READY`.

## 2026-09-01 / 442c0427 + ND3-250 worktree / viewmodel motion vectors

- Tester/machine label: local Windows development machine; runtime visually checked by user.
- Branch and base commit: `feature/neural-rendering-spike`, `442c0427`.
- Build configuration: `RelWithDebInfo`, VS2022 x64, DX12 only.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Scene/save/map: disposable `devmap game/mars_city2`; weapon and ammunition granted through the local console.
- Relevant cvars: `r_neuralViewmodelMotionVectors 1`, diagnostic `r_neuralDebug 2`; feature-off smoke used both at `0`.

| Test | Result | Evidence | Notes |
|---|---|---|---|
| Configure and build | PASS | configure/build output; staged executable | C++ linked; 758 existing DXIL jobs current; SHA-256 `EE673ABDA9566656B5DCE3344C519478636793E6E5A6F632F64F9A5BF6436167`. |
| Normal viewmodel presentation | PASS | user manual observation before enabling mode `2` | Granted weapon equipped and rendered normally on `game/mars_city2`. |
| T08 weapon bob/turn/recoil | PASS | user manual combined walk/turn/fire test | Viewmodel motion diagnostic worked without reported disappearance, depth flicker, trails, corruption, or crash. |
| Intro-map restriction | PASS / test correction | source inspection and user observation | Opening save intentionally held the weapon lowered despite inventory grant; disposable post-intro map removed the scripted restriction. |
| Feature-off startup regression | PASS | automated local DX12 launch | With viewmodel motion and diagnostics off, process remained alive after ten seconds and closed normally. |

### Performance

- Baseline and changed frame time: not measured.
- Feature-off adds no viewmodel palette upload or velocity draw. Enabled mode reuses the skinned object path for visible weapon surfaces.

### Regressions and limits

- None observed in the tested opaque viewmodel path.
- Muzzle flash/translucency remains unclassified and is assigned to ND3-260 reactive/transparency masks.

### Conclusion

ND3-250 and T08 pass. Shared scene color/depth with independently enabled viewmodel velocity is the accepted neural-input policy; ND3-260 is `READY`.

## 2026-09-01 / e63f0bb9 + ND3-240 worktree / skinned-object motion vectors

- Tester/machine label: local Windows development machine; runtime visually checked by user.
- Branch and base commit: `feature/neural-rendering-spike`, `e63f0bb9`.
- Build configuration: `RelWithDebInfo`, VS2022 x64, DX12 only.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Scene/save/map: resumable Mars City scene with a nearby talking marine.
- Relevant cvars: diagnostic `r_neuralDebug 2`; feature-off `r_neuralDebug 0`; `r_neuralSkinnedMotionVectors` defaults to `0` and is forced by diagnostic mode `2`.

| Test | Result | Evidence | Notes |
|---|---|---|---|
| Configure and build | PASS | configure/build output; staged executable | 758 DXIL jobs; C++ linked; executable SHA-256 `A77F5FF4E870C7461807AB3AAB04A06841605BB0660DB20CA3BB8918F62DD923`. |
| T06 animated MD5 / static camera | PASS | user manual observation | Talking marine's helmet/body triangles showed subtle independent signed-color shimmer; static field remained mostly neutral. |
| T07 animated MD5 / moving camera | PASS | user manual observation | Forward movement and mouse rotation retained the coherent camera field while the skinned contribution remained stable; no corruption or crash reported. |
| Joint-history initialization | PASS | source review and stable runtime | First/non-consecutive sample and joint-count changes suppress pose velocity; no frame-local GPU handle is retained. |
| Feature-off startup regression | PASS | automated local DX12 launch | With both skinned controls off, process remained alive after ten seconds and closed normally. This was a startup smoke, not a fresh visual comparison. |

### Performance

- Baseline and changed frame time: not measured.
- Feature-off performs no joint-history scan/upload. Enabled mode adds one previous-palette upload per visible tracked actor and extra draws for changed opaque skinned surfaces.

### Regressions and limits

- None observed in the tested conversational animation or moving-camera scenario.
- Perforated/translucent surfaces, CPU deforms, viewmodel velocity, crowded-scene joint-cache pressure, and explicit history resets remain untested.

### Conclusion

ND3-240 passes T06 and T07. ND3-250 viewmodel ordering/velocity is now `READY`.

## 2026-09-01 / c9c5e063 + ND3-230 worktree / rigid-object motion vectors

- Tester/machine label: local Windows development machine; runtime visually checked by user.
- Branch and base commit: `feature/neural-rendering-spike`, `c9c5e063`.
- Build configuration: `RelWithDebInfo`, VS2022 x64, DX12 only.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Scene/save/map: resumable user save in Mars City Hangar with a visible moving rigid object.
- Relevant cvars: diagnostic `r_neuralDebug 2`; feature-off `r_neuralDebug 0`; `r_neuralRigidMotionVectors` defaults to `0` and is forced by diagnostic mode `2`.

| Test | Result | Evidence | Notes |
|---|---|---|---|
| Configure and build | PASS | build output; `docs/neural-rendering/LAST_BUILD.txt` | 754 DXIL jobs; C++ linked; executable staged. |
| T04 stationary camera / moving rigid object | PASS | user manual observation | Moving object formed a distinct signed-color silhouette while the static environment remained neutral. |
| T05 rigid physics object | PASS | user manual observation | Physics prop produced object-local velocity while moving and returned to neutral after settling; no persistent trail or crash reported. |
| History initialization | PASS | source review and stable runtime | First/non-consecutive observation collapses previous transform to current. |
| Feature-off regression | PASS | user manual observation with `r_neuralDebug 0` | Normal scene, HUD, menus, and gameplay; no crash. |

### Regressions and limits

- None observed in the tested opaque rigid path or feature-off runtime.
- Perforated, translucent, skinned, GUI, subview, and viewmodel surfaces are intentionally excluded from this slice.

### Conclusion

ND3-230 passes T04, T05, and the feature-off regression. ND3-240 skinned pose history is now `READY`.

## 2026-09-01 / d6d361fa + ND3-220 worktree / signed motion-vector diagnostic

- Tester/machine label: local Windows development machine; runtime visually checked by user.
- Branch and base commit: `feature/neural-rendering-spike`, `d6d361fa`.
- Build configuration: `RelWithDebInfo`, VS2022 x64.
- CMake options: established DX12-only configuration.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Resolution / HDR / AA: runtime tests at the current window size; validation capture at 1725x985; `_taaMotionVectors` is `R16G16_FLOAT`; TAA active.
- Scene/save/map: resumable user save in Mars City Hangar.
- Relevant cvars: `r_graphicsAPI dx12`, `r_neuralDebug 2`; capture additionally used `r_fullscreen 0` and `r_logLevel 1`.

| Test | Result | Evidence / artifact path | Notes |
|---|---|---|---|
| Configure and build | PASS | build output; `docs/neural-rendering/LAST_BUILD.txt` | 750 DXIL jobs, including the new diagnostic shader; engine executable staged. |
| T01 static camera/static world | PASS | user manual observation | Output settled to neutral gray, representing zero pixel displacement. |
| T02 camera yaw | PASS | user manual observation and ignored RenderDoc frame 1811 | Smooth coherent signed field; no scene-color or GUI contamination. |
| T03 lateral translation | PASS | user manual observation | Nearby geometry showed stronger variation than distant geometry. |
| Weapon exclusion | PASS | user manual observation | Weapon remained neutral, matching the existing alpha exclusion policy. |
| GPU resource/order | PASS | ignored `captures/neural/renderdoc-motion-debug/motion_debug_frame1811.rdc` | `R16G16_FLOAT` motion resource generated before dedicated debug presentation. |
| Feature-off regression | PASS | user manual observation with `r_neuralDebug 0` | Loaded save; world, HUD, menus, and gameplay rendered normally with no crash. |

### Performance

- Baseline frame time: not measured.
- Changed frame time: not measured.
- Mode `0` adds no debug draw. Mode `2` adds one fullscreen visualization blit; motion generation is forced only if it would otherwise be disabled.

### Regressions

- None observed in mode `2` operation or the feature-off mode `0` regression check.
- Rigid and skinned object motion remains unimplemented.

### Conclusion

ND3-220 passes for camera/static-world visualization and moves ND3-230 rigid-object history to `READY`.

## 2026-09-01 / 992b6355 + Phase 3 worktree / HUD-free LDR diagnostic

- Tester/machine label: local Windows development machine; runtime visually checked by user.
- Branch and base commit: `feature/neural-rendering-spike`, `992b6355`.
- Build configuration: `RelWithDebInfo`, VS2022 x64.
- CMake options: `FFMPEG=OFF`, `BINKDEC=ON`, `USE_DX12=ON`, `USE_VULKAN=OFF`; established `/wd4530` and Windows SDK DXC overrides.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Resolution / HDR / AA: 1280x720 validation capture; output resource `R8G8B8A8_UNORM`; TAA active.
- Scene/save/map: resumable user save in Mars City Hangar.
- Relevant cvars: `r_graphicsAPI dx12`; `r_neuralDebug 0` and `1`; RenderDoc capture additionally used `r_fullscreen 0` and `r_logLevel 1`.

| Test | Result | Evidence / artifact path | Notes |
|---|---|---|---|
| DX12 configure | PASS | `docs/neural-rendering/LAST_CONFIGURE.txt` | VS2022 x64; DX12 only. |
| RelWithDebInfo build | PASS | build output; `docs/neural-rendering/LAST_BUILD.txt` | Engine and staged executable produced successfully. |
| Executable identity | PASS | staged `RBDoom3BFG.exe` | 24,733,696 bytes; SHA-256 `7CF004A5F949E743E6D137B1685F60B00E3BD995773FA2FBDE30D9C4080B59C3`. |
| T18 feature disabled | PASS | user manual observation with `r_neuralDebug 0` | Normal world, HUD, and menus; no crash or visual regression observed. |
| T14 HUD-free debug present | PASS | user manual observation with `r_neuralDebug 1` | World and weapon remain; overlay HUD and menus are absent. |
| GPU ordering | PASS | ignored `captures/neural/renderdoc-hudless/hudless_frame1567.rdc` | Postprocess -> capture -> GUI -> HUD-free present; capture converted to XML successfully for marker inspection. |
| Snapshot resource | PASS | same RenderDoc capture; XML conversion used for local inspection | Full 1280x720 copy from resource 413 `_currentRenderLDR` to resource 414 `_neuralHudlessLDR`; correct NVRHI barriers recorded. |
| T17 live resize recreation | PASS | user manual observation in windowed mode `1` | HUD-free rendering continued after resizing with no black frame, corruption, or crash. |

### Performance

- Baseline frame time: not measured.
- Changed frame time: not measured.
- Mode `0` adds one allocated 1280x720 RGBA8 intrinsic texture but no per-frame copy. Mode `1` adds one full-resolution texture copy and one final fullscreen blit.

### Regressions

- None observed in feature-off or feature-on runtime checks.
- Debug mode intentionally makes overlay menus invisible; `Alt+F4` was used to exit.

### Conclusion

ND3-200 and ND3-210 pass. Phase 3 has a measured HUD-free display-referred boundary; camera/static motion-vector validation is the next narrow task.

## 2026-08-31 / ea29c006 / upstream DX12 baseline

- Tester/machine label: local Windows development machine; runtime visually checked by user.
- Branch and commit: `feature/neural-rendering-spike`, upstream `ea29c006e84fedcc0e7c173c383a087ce0a8c0d5` plus documentation/helper changes.
- Build configuration: `RelWithDebInfo`, VS2022 x64.
- CMake options: `FFMPEG=OFF`, `BINKDEC=ON`, `USE_DX12=ON`, `USE_VULKAN=OFF`; local `/wd4530` compatibility flag; Windows SDK DXC override.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Resolution / HDR / AA: 1280x720 capture; `R16G16B16A16_FLOAT` HDR scene; single-sample depth/motion/LDR; TAA pass active.
- Scene/save/map: resumable user save in Mars City Hangar.
- Relevant cvars: `r_graphicsAPI dx12`, `r_logLevel 1`, windowed capture; full console cvar dump remains pending.

| Test | Result | Evidence / artifact path | Notes |
|---|---|---|---|
| Prerequisite check | PASS | `Check-Prerequisites.ps1` console report | VS, CMake, Git, ISPC, data, and four submodules detected. |
| DX12 configure | PASS | `docs/neural-rendering/LAST_CONFIGURE.txt` | VS2022 x64; DX12 only. |
| RelWithDebInfo build | PASS | `docs/neural-rendering/LAST_BUILD.txt` | 749 DXIL shader jobs; executable produced and staged. |
| Executable identity | PASS | ignored `captures/neural/20260831-220206/baseline-metadata.md` | SHA-256 `8EEF627AA8B7BEDA5E89FFD2410C3E94B549530CC01F45484FCEB7D46946F2BA`. |
| Baseline launch | PASS | user manual observation | DX12 observed; new game rendered; save created; clean exit. |
| Stationary temporal baseline | PASS | ignored `captures/neural/renderdoc-baseline-pass2/baseline_frame1487.rdc` | Zero motion target; full marked event stream; no replay problems. |
| Forward camera motion | PASS | ignored `captures/neural/renderdoc-motion/lateral_frame1469.rdc` | Nonzero signed field converges toward vanishing point; filename says lateral but movement was forward. |
| Resource format audit | PASS | `RECON_REPORT.md` | HDR RGBA16F, depth D24S8, LDR RGBA8, motion RG16F at 1280x720. |
| HUD ordering audit | PASS | stationary capture EID sequence in `RECON_REPORT.md` | Scene post-processing completes before GUI standard-shader stage mutates LDR. |
| Rigid/skinned/transparency matrix | BLOCKED | | Requires diagnostics and later incremental motion work. |
| Feature-off regression | PASS | upstream baseline contains no neural/SDK renderer changes | Documentation/helper-only checkpoint. |

### Performance

- Baseline frame time: not measured.
- Changed frame time: not applicable; no renderer changes.
- Measurement method: pending GPU capture.

### Regressions

- None observed in the baseline launch.
- Full rendering regression matrix has not been run.

### Conclusion

Phase 1 baseline and Phase 2 reconnaissance/capture gates are passed. Phase 3 may begin with the OFF-by-default diagnostic output-separation scaffold.

Use one section per tested commit/configuration. Include failures; do not rewrite history to show only successful runs.

## Result template

```markdown
## YYYY-MM-DD / commit / task

- Tester/machine label:
- Branch and commit:
- Build configuration:
- CMake options:
- GPU and driver:
- Resolution / HDR / AA:
- Scene/save/map:
- Relevant cvars:

| Test ID | Result | Evidence / artifact path | Notes |
|---|---|---|---|
| T01 | PASS/FAIL/BLOCKED | | |

### Performance
- Baseline frame time:
- Changed frame time:
- Measurement method:

### Regressions
-

### Conclusion
-
```


## 2026-09-06: HUD settings and downstream identity

- Added System Options HUD Layout and HUD Size fields with matching enum/control ordering, change detection and existing archive commit behavior. HUD preferences do not participate in restart detection. The render path recalculates layout from the current viewport each frame; new configs default to centered 16:9, while saved overrides remain intact.
- Updated Licensee.h game title/branch and Windows executable metadata to neuralDoom, preserving upstream credits and save/config identifiers.
- Build-RBDOOM.ps1 -Configuration RelWithDebInfo passed for both build (SDK OFF) and build-streamline (SDK ON); logs: captures/neural/hud-settings-build-off.log and hud-settings-build-on.log.
- Test-NeuralBuildIdentity.ps1 passed exact-target, stale-output/configuration isolation, missing-output and script syntax checks.
- Native 2560x720, aspect 1.777778, scale 1.15: PASS, captures/neural/smoke-20260906-120459-41267828. Inspected after.png: centered health/ammo and full-width world rendering. DLAA 2560x720, aspect 1.777778: PASS, captures/neural/smoke-20260906-120607-d4a602b7. Both advanced 64 primary frames and passed reset/capture/backend checks. DLAA used normal GPU access outside the restricted sandbox.
- Commit-guard fixtures rejected a dummy forbidden runtime filename and a staged machine path even after the working file was cleaned; accepted clean staged text. Initial sandbox PowerShell launch failed from language-mode restrictions; the same checks passed with normal process access.
- Focused diff review covered enum ordering, live cvar reads, archive/change detection, restart behavior, upstream attributes and branding compatibility. Interactive menu navigation, save/relaunch persistence and live window-resize visual tests remain pending; runtime smoke checks use explicit HUD values and do not exercise those UI flows.
- Git setup uses origin ecarmen16/neuralDoom and upstream RobertBeckebans/RBDOOM-3-BFG. Remote provisioning/push remains pending repository availability and authenticated GitHub CLI. No proprietary payloads are included in the source checkpoint.
- Next: validate menu interaction and resize persistence, then implement the first native HDR capability/output negotiation slice described in MODERNIZATION_PLAN.md.


## 2026-09-06: native HDR prototype and HUD verification

Implementation on `codex/native-hdr` starts from `9174f4ca`. The task's source checkout is now populated; implementation is synchronized to the established local game/build checkout without moving game data or reusing its CMake cache in a different directory.

### HUD and menu checks

A bounded local window-message helper targeted only the game process it launched, with disposable saves/configuration under `captures/neural/hud-ui-check`. Inspected pause/settings/System Options captures. Changed HUD Layout to centered 21:9 and HUD Size to 115%, left the menu, and observed archived values `2.333333` and `1.15`. Changed resolution through `vid_restart` at 1680x720, 2560x720 and 1280x720; inspected the 32:9 screenshot for the adjusted HUD region. A fresh launch read back both saved values. Original user configuration was not used. Broader combat/notification/PDA states remain outside this check.

A second isolated run under `captures/neural/hud-hdr-ui-check` exercised the new HDR brightness menu fields. Inspected `screenshots/hdr_controls.png`: all four labels and values fit the menu. Two menu sessions increased scene/UI white to 220 nits and peak to 1100; the config and console reported those values after leaving the menu. The HDR output restart prompt is wired through the existing IsRestartRequired path and reviewed in source; accepting that prompt was not part of this UI test.

### Build and GPU checks

- Configured DX12 RelWithDebInfo and built SDK OFF (`build`) and SDK ON (`build-streamline`). Changed tone-mapping/blit shader permutations compiled to DXIL. Final build logs: `captures/neural/native-hdr-build-off.log` and `native-hdr-build-on.log`.
- Exact artifact/missing/stale/wrong-config fixtures and all PowerShell syntax checks passed. The source audit and whitespace checks passed before the final commit hook.
- Windows output discovery reported scRGB transport support, Windows HDR inactive, 8-bit desktop output and reported peak 1499 nits. That is current desktop state and reported metadata, not monitor calibration or proof of active HDR.
- Native and DLAA HDR diagnostics preserved finite composition values above 1 before the SDR preview conversion. The readback retains row pitch and the specific rendered swapchain texture, rather than reading the next DXGI buffer. Final SDR scRGB presentation stayed at or below 1, with zero nonfinite or negative values. DLAA continued evaluating/presenting without rejection through resize.
- Default SDR gameplay, 32:9-to-16:9 resize, automatic SDR fallback and selected retro mode all passed. All recorded smoke runs below advanced 64 primary frames; resize cases advanced the temporal-history epoch and produced the requested PNG dimensions.

| Run directory under captures/neural | Scenario | Result |
|---|---|---|
| smoke-20260906-123753-246dfaf3 | SDK-OFF native HDR shader diagnostic, 1680x720 to 2560x720 | PASS; initial composition readback implementation |
| smoke-20260906-124054-a019aeba | SDK-ON DLAA HDR diagnostic, 1680x720 to 2560x720 | PASS; both composition and scRGB readbacks |
| smoke-20260906-124934-27eff540 | SDK-OFF SDR, 2560x720 to 1280x720 | PASS; inspected gameplay capture |
| smoke-20260906-124958-e259a1f6 | SDK-OFF AutoHDR on SDR desktop, 1280x720 | PASS; inspected gameplay capture and bounded presentation |
| smoke-20260906-125020-6e73c139 | SDK-OFF AutoHDR with retro render mode 1 | PASS; SDR content/presentation preserved |
| smoke-20260906-125209-c8014c01 | SDK-ON DLAA HDR diagnostic, 2560x720 to 1680x720 | PASS; reverse resize |

### Failures addressed and validation limits

- Initial AutoHDR fallback run `smoke-20260906-123440-10db4c8f` failed a check that conflated negative legacy composition values with nonfinite values. FP16 exposes negatives/overshoot previously clamped by UNORM targets. Diagnostics now report them separately, reject nonfinite composition and verify that final presentation clamps to the supported range with no negative/nonfinite pixels. This retains the existing SDR effect processing while enforcing the presentation contract.
- Two launch attempts exited before creating logs because the menu test already owned Doom 3's single-instance mutex. The runner now checks that mutex before launching, and gameplay checks run sequentially. Those attempts are not counted as passes.
- The temporary UI helper initially consumed a stale ready marker on relaunch; its log is now cleared before process creation. An unquoted hyphen in a screenshot filename triggered the engine console's argument parser; a subsequent capture with a simple filename succeeded. These were test-harness issues, with disposable output only.
- An attempted SPIR-V shader check was unavailable: the installed Windows SDK DXC reports that SPIR-V CodeGen was not compiled in. Vulkan build/runtime validation remains pending; the shared interface provides SDR defaults and no Vulkan backend implementation was removed.
- Actual Windows-HDR-enabled gameplay, monitor movement/HDR-toggle transitions, unavailable color-space failure injection, perceptual calibration, motion/ghosting comparisons and comprehensive performance measurements remain pending. The implementation preserves legacy gamma-space HUD blending; it does not yet provide physically linear UI composition or HDR-aware legacy filmic effects. The embedded NR bridge stays on its SDR transport.
- Focused review covered format/color-space pairing, startup/resize failure handling, default-SDR polling cost, scene/UI brightness separation, constant-buffer agreement, exact presentation conversion placement, retained swapchain readback, menu enum ordering/change tracking, and isolated smoke artifacts. No new dependency was introduced.

Next: validate HDR-enabled display behavior/calibration, then measure existing lighting/shadow/reflection passes before choosing the first lighting refinement. Keep geometry experiments on a later focused branch.

Final revision verification after limiting display polling to scRGB mode:

- `smoke-20260906-125537-f75e6bee`: Native, SDR, diagnostic=False, 64 primary frames, PASS. Executable SHA-256: `6593A16BDB1F0633BBC26C0FBBF18E9BFED44A6A90EB5B043968863E34E1E59A`.
- `smoke-20260906-125601-2d6d8ba1`: DLAA, AutoHDR, diagnostic=True, 64 primary frames, PASS. Executable SHA-256: `2B5850976E667C03A3348D7E90BF0651864676B08F9C0448F3FD751428FD380A`.

## 2026-09-06: unattended lighting diagnostics

Branch `codex/lighting-diagnostics`, based on `953d6904`. No shader, image format,
coordinate convention, lighting default or vendor dependency changed. Added
`r_gpuProfileFrames` in `neo/renderer/RenderLog.{h,cpp}` and the GPU CSV reader,
lighting comparison runner, reader fixtures and optional smoke-run profiling under
`tools/neural-rendering`. See `LIGHTING_BASELINE.md` for the contract and numbers.

### Build and validation

- `Configure-RBDOOM-DX12.ps1 -BuildDirectory build` followed by
  `Build-RBDOOM.ps1 -BuildDirectory build -Configuration RelWithDebInfo -Parallel 16`:
  PASS. Repeated with `-BuildDirectory build-streamline`: PASS, existing official
  SDK enabled. Existing Windows SDK string-macro warnings remain. DXIL shaders
  were unchanged/up to date; Vulkan was not built or run in this task.
- SDK-OFF tested executable SHA-256:
  `3CFD13CCA81F3AAAEB5EB54FD4099DE76433ABBCCC22E581337EDE75DCADA373`.
- SDK-ON tested executable SHA-256:
  `71F4681A8F9742F0ACD26197A28D5A6E8327883B77275991BB30885E20DCF180`.
- Test manifests record base commit `953d6904` with the diagnostics patch dirty;
  exact hashes bind the results to the executables. Final source synchronization
  and commit do not substitute a different executable for these measurements.
- `Test-NeuralGpuProfile.ps1`: PASS for units, median/p95, missing versus zero,
  invalid/negative/nonfinite/zero total timing, incomplete CSV, duplicate frames
  and wrong dimensions. `Test-NeuralBuildIdentity.ps1`: PASS, including all helper
  PowerShell syntax and exact/missing/stale/configuration artifact checks.
- Focused review covered query-ring attribution and warmup, bounded allocation,
  cancellation/restart/completion, absent query export, post-capture file I/O,
  existing query synchronization, isolated cvars, statistical scope, backend
  gating, and preservation of the default smoke scenario. Whitespace/source
  audits passed; staged new files are checked again by the commit hook.

### Runtime evidence

All paths below are under the build checkout's ignored `captures/neural` directory.

| Artifact | Scenario | Result |
| --- | --- | --- |
| `smoke-20260906-131738-b52894cd` | Initial Native 2560x720, 64 GPU samples | PASS; inspected gameplay PNG |
| `lighting-20260906-131917-fc736ea1/lighting.json` | Eight 2560x720 pilot runs, 300 samples each | Functional PASS; timing noise makes this unsuitable for marginal-cost claims |
| `lighting-20260906-132418-8c1128b8/lighting.json` and `smoke-20260906-132418-9041577e` | Requested 5120x1440 window | FAIL: Windows clamped the client to 5104x1401; reader correctly rejected the mismatch |
| `lighting-20260906-132554-7a6c8356/lighting.json` | Eight Native 4800x1350 runs, 600 warmup/300 samples each | PASS; fixed-tick mode, reversed order, all temporal/PNG/GPU checks |
| `smoke-20260906-133042-3af9999d`, `smoke-20260906-133102-d7b6671c` | Two DLAA Baseline 4800x1350 runs, same warmup/samples | PASS; evaluated/presented with zero rejection; bypassed TAA absent in all samples |
| `smoke-20260906-133122-36fe6903` | SDK-OFF Native 1280x720, profiling disabled | PASS; no GPU CSV created |
| `smoke-20260906-133145-19f47621` | 1-sample completion, 3600-to-3500 request restart, cancel, then new 64-sample request | PASS; exactly two completion markers (1 and 64), final CSV contains 64 valid samples |

The lifecycle scenario used an ignored copy of the smoke runner with only its cfg
sequence extended. It did not drive the user's active game or configuration.
All 20 PNGs from the ten final comparison runs passed CRC, full pixel-stream
decompression, dimensions and scanline-filter checks at 4800x1350. Full-size preview
tooling returned base64 transport errors. A first verification attempt lacked
Pillow; the check was completed with Python's standard library. Visual inspection
was limited to the smaller pilot capture; no perceptual DLAA comparison is claimed.

### Interpretation and limits

GPU: RTX 5090, NVIDIA 610.47 / UMD 32.0.16.1047. OS build: 26100.9168 (24H2).
The pilot's median GPU intervals varied from roughly 1.5 to 3.8 ms; a bounded
read-only `nvidia-smi` log also observed P0/P8 and memory-clock changes. Source
inspection identified the engine's inactive-window 15-Hz sleep. Profiling now uses
existing `com_fixedTic=1` to bypass that sleep, while normal smoke/play keeps its
normal timing. No system clock/power policy was changed. The final workload has
closely agreeing repeated medians/p95; this does not prove stable clocks everywhere.

See the table in `LIGHTING_BASELINE.md` for the final per-configuration ranges.
These are graphics-queue intervals for one active-world spawn scene, not FPS,
end-to-end latency, or a broad GPU recommendation. The existing SSR counter is
unwired; empty CSV cells preserve unavailable data. Likewise, DLAA evaluation has
no standalone timer and should not be inferred from a missing TAA sample.

The current scene logs 392 missing environment-image warning lines plus existing
startup/resource/content warnings. Probe-lighting quality is therefore not a
validated baseline. Bridge/NR appearance, HDR calibration, motion artifacts and
other maps remain outside this timing task. Next: audit missing probe loading and
fallbacks, then add two representative fixed-camera lighting scenarios.
