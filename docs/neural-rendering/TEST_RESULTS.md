# Test results

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
