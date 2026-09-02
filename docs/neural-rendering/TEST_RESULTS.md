# Test results

## 2026-09-01 / 71392b90 + ND3-320 worktree / Streamline core lifecycle

- SDK build: `USE_STREAMLINE=ON`, official local Streamline `v2.12.0`.
- Runtime controls: `r_streamlineEnable 1`, `r_streamlineApplicationId 0`, DX12, windowed, core-only mode.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.

| Test | Result | Evidence |
|---|---|---|
| Default SDK-OFF build | PASS | Established configure/build helper compiled stubs and linked `RelWithDebInfo` without an SDK dependency. |
| SDK-ON build/runtime staging | PASS | Isolated build linked and copied the four required local runtime DLLs beside the ignored executable. |
| Early core initialization | PASS | Ignored `captures/neural/streamline-smoke/base/streamline_core.log`: `Streamline initialized in core-only mode`. |
| Native D3D12 device handoff | PASS | Same log: RTX 5090 device created, followed by `Streamline accepted the native D3D12 device`. |
| Startup fallback | PASS | Hidden process remained alive after ten seconds; DLSS was explicitly not requested with application ID 0. |
| Ordered shutdown | PASS | A 120-frame scripted run processed engine `+quit` and exited normally with code 0 after the Streamline-enabled initialization path. |

The reversible core lifecycle is validated. DLSS support/evaluation remains untested and unavailable until a valid NVIDIA-issued application ID is provided; native presentation remains the active fallback.

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
