# Test results

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
