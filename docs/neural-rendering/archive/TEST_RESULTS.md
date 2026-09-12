## 2026-09-06 - Material reflection checkpoint and CPU-only validation

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../README.md) for current guidance.

Code checkpoint: `a8ddea9be2daeea15da5a04b6701df993b33c25f` on `codex/rt-foundation`. Both source and game checkouts were synchronized and clean before the final build-manifest refresh. This subsequent results-only documentation commit changes no renderer code or compiled artifacts.

| Configuration | Result | EXE SHA-256 | Manifest shaders |
|---|---|---|---:|
| Native DX12, RT ON, SDK OFF (`build-rt`) | BUILD PASS | `05C0CAAC2893ADC00F4D68525D3C1E53E2C64ACEB11EB689D32487D7867F6B17` | 151 |
| DX12 DLAA, RT ON, SDK ON (`build-streamline`) | BUILD PASS | `F73995599EE238C0367C318ED19865D3F140F62F4C40E05C5D1643032E83769B` | 151 |
| DX12 baseline, RT OFF, SDK OFF (`build`) | BUILD PASS | `3A9EC7903CC819543C3E08E4A5B4AF79EDEE42D15555362DBC4BEBAEE94DECAB` | 141 |

All three existing trees were configured with `Configure-RBDOOM-DX12.ps1 -RepoRoot <game-checkout> -BuildDirectory <tree> -RayTracing ON|OFF` and built with `Build-RBDOOM.ps1 -RepoRoot <game-checkout> -BuildDirectory <tree> -Configuration RelWithDebInfo`. The optional SDK setting and pinned dependencies were retained. Final schema-2 manifests record the code checkpoint above, `dirty=false`, the exact EXE hash and matching shader bytes. Every listed shader and executable was independently rehashed after all builds. RT configurations include ten raw ray shaders; the RT-OFF manifest excludes those shaders.

Validation performed:

- Native RT, optional DLAA and RT-OFF compilation passed, including all material capture permutations and SM 6.5 reflection stages. Build logs are `captures/neural/reflections-build-rt-final.log`, `reflections-build-streamline-final.log` and `reflections-build-final.log`; final clean identity confirmations use corresponding `-clean.log` names. Configure logs use `reflections-configure-<tree>.log`. Existing Windows SDK `StrCmp*` C4005 warnings remain; no compiler errors in the final builds.
- `Test-ReflectionShaderContract.py --repo-root <game-checkout> --dxc <Windows-SDK-dxc>` passed **64 exact order-sensitive engine shader lookups**, baseline/capture MRT output signatures, all three reflection compute register layouts, 192/112-byte constant buffers and 8x8 dispatch sizes. A deliberate macro-order mutation failed with the expected missing engine permutation. The initial code review caught and fixed that startup risk before handoff. Output: `captures/neural/reflections-shader-contract.log`.
- `Test-NeuralBuildIdentity.ps1` and `Test-NeuralSetup.ps1` passed their offline target/manifest/shader/read-only setup fixtures and PowerShell parser checks. An extra interactive parser invocation hit restricted PowerShell language mode; the existing parser test then passed in the approved full-language test run. Logs: `reflections-build-identity.log` and `reflections-setup-fixtures.log` under `captures/neural`.
- Both real Native/DLAA `Setup-NeuralDoom.ps1 -ValidateOnly` checks passed after clean manifests were written. Both full RTX launcher command lines (all four effects and AutoHDR) also passed `Start-NeuralDoom-Dogfood.ps1 -ValidateOnly`, including the engine's command-line size limit. No game was launched. Logs: `reflections-setup-native.log`, `reflections-setup-dlaa.log`, `reflections-launch-ready-native.log`, `reflections-launch-ready-dlaa.log`.
- Focused review checked native target-0 preservation, matching capture layer/response, skinned shader metadata, order-sensitive permutations, shared atlas/radiance lifetimes, optional framebuffer ownership, history/viewport reset and current-miss rejection, debug isolation, finite FP16 composition and all-off/compiled-out control flow. Material response was moved after filtering to avoid borrowing reflectivity from neighbors/history. GPU behavior is not established by this review.
- `git diff --check` and the clean public-source audit passed (2,486 tracked files); NVRHI and ShaderMake remained clean at their existing pins. No assets, SDK binaries, runtime blobs, personal settings, captures or machine paths were staged. A pre-commit audit invocation without `-AllowDirty` reported the expected dirty-tree guard; the staged pre-commit check and subsequent clean audit passed.

Runtime boundary: **no GPU/gameplay test was performed for the reflection addition**, with manual visual acceptance pending. The preceding material-lighting playtest identified excessive bounce brightness. The GI default and the existing local saved value were changed from 1.5 to 1.125, with a local configuration backup. This is configuration evidence, not measured reflection image quality.

The opt-in smoke harness now checks reflection coverage, full-resolution dimensions, live off/on/resume, resize and all seven debug views; that scenario remains unrun. Reflection material response, noise/trails, dynamic-object omissions, screen-edge fallback, 5120x1440 performance and Native/DLAA/HDR visual quality require the [three-check playtest](../RAY_TRACED_REFLECTIONS.md#three-check-playtest). Static BSP-only geometry, approximate hit shading and limited current-view light lists remain explicit limitations. Next bounded implementation task: rigid dynamic ray instances for doors and props.

---

## 2026-09-06 - Review fixes, clean builds and CPU-only handoff

Final code checkpoint: `7a5ecc6a89536b2507e4ed8fcc64e9e91e2acf44` on `codex/rt-foundation`. Both source and game checkouts were synchronized and clean before build-manifest refresh. This later results-only documentation commit does not change the tested code or shader artifacts.

| Configuration | Result | EXE SHA-256 | Manifest shaders |
|---|---|---|---:|
| Native DX12, RT ON, SDK OFF (`build-rt`) | BUILD PASS | `C0248D63A498AE05F43D6C9E81BA5F109350CCCA00A5EB14AD5138CD1CCE38DD` | 148 |
| DX12 DLAA, RT ON, SDK ON (`build-streamline`) | BUILD PASS | `AEDCFE0B22B6D2346FBABD6CA2D6ED8AB8169348019B3741B42F09185A849819` | 148 |
| DX12 baseline, RT OFF, SDK OFF (`build`) | BUILD PASS | `CCD9EC7609AFEF6DEF984B917D7CDA91B70B2AA46305B7FED166650C3F4C7CF9` | 141 |

All use `Build-RBDOOM.ps1 -RepoRoot <game-checkout> -BuildDirectory <tree> -Configuration RelWithDebInfo`. The existing configured CMake trees and pinned dependencies were retained. Final schema-2 manifests record the clean code commit above, `dirty=false`, matching executable SHA-256 and matching compiled shader bundles. In particular, the shared raw RT shaders and rigid/skinned shader variants match both rebuilt RT executables. Build logs: source-workspace `captures/neural/review-build-rt-final.log`, `review-build-streamline-final.log`, `review-build-final.log`; clean incremental confirmation logs end in `-clean.log`. Compiler warnings were the Windows SDK C4005 `StrCmp*` redefinitions; no compiler errors.

`Test-NeuralBuildIdentity.ps1` and `Test-NeuralSetup.ps1` passed. These exercise exact CMake target selection, stale output and missing configuration, invalidation of a previous success manifest when the output is absent, all PowerShell parsers, missing/changed EXE, empty/nonempty replacement shader, old manifest, missing lighting data, and read-only setup behavior. Cleanup fixtures reject source/repository/asset/outside targets and accept only a matching dedicated CMake build directory; they do not delete anything.

Both real `Setup-NeuralDoom.ps1 -Profile Native -ValidateOnly` and `-Profile DLAA -ValidateOnly` passed after the final builds. All three manifests were independently compared against current executable and shader bytes. `git diff --check`, the staged public-source audit (2,479 files) and focused review passed. NVRHI and ShaderMake pins are unchanged. No retail files, SDK binaries, captures, credentials or machine paths were staged.

The renderer fixes are automatic neural-backend joint history, object-motion raster/depth agreement with unjittered output vectors, and automatic history invalidation after RTX cvar edits. The smoke helper now checks lighting-change resets without supplying manual resets for GI/contact toggles, but that updated GPU scenario has not been run.

**No game was launched during this review.** These results prove compilation and local setup integrity, not final GPU stability or image quality. Live character/weapon motion, RTX cvar transitions, albedo mode 4, map/save reload, new material-shader fallback, and the combined 5120x1440 DLAA/HDR/RTX path remain pending on these exact binaries. RT-OFF compilation passed; its latest runtime regression check is also pending. Prior gameplay results below apply to their own recorded artifacts.

See [the review and three-check playtest](REVIEW_2026-09-06.md). No new graphical feature was added during review; full render resolution is retained. Publication remains separate from build validation.

# Test results

## 2026-09-06 — RTX material lighting, GPU pause checkpoint

Implemented full-resolution textured diffuse bounce/emission, contact shadows, AO controls and bindable comparison commands in `RayTracingDiagnostic.cpp`, with opaque-light and pre-temporal hooks in `RenderBackend.cpp`/`RenderCommon.h`, updated capability text in `RenderSystem_init.cpp`, and SM6.5 shaders under `neo/shaders/rt`. Resource formats, coordinates, shading scope and controls are documented in [RTX_LIGHTING.md](../RTX_LIGHTING.md).

`Build-RBDOOM.ps1 -BuildDirectory build-rt -Configuration RelWithDebInfo` passed. Native smoke `smoke-20260906-192933-7ef79bd1` passed with AO, contacts, material GI, live off/on, debug views, example key bindings and 1280×720 → 1920×1080 resize under native DX12/NVRHI validation. GPU samples reported zero invalid contact/GI values. The earlier native DX12 error 538 was caused by NVRHI retaining a framebuffer binding across the HDR snapshot copy; clearing the command-list state after the copy and invalidating the engine vertex-buffer cache fixed the reproduced error. No submodule changes were needed.

No further runtime checks were performed at this checkpoint. Final albedo-debug/empty-light-state edits have not been rebuilt. SDK-ON, RT-OFF, 5120×1440 HDR/DLAA, new-resource map reload and fallback checks remain pending. [CHECKPOINT.md](CHECKPOINT.md) records the precise tested artifact, completed CPU installer tests, known visual limits and resume steps. This is an implementation checkpoint, not a release validation claim.


## 2026-09-06 — Ultrawide feedback and narrower FOV control

User dogfood feedback: brighter/smoother appearance with AO enabled, ultrawide
HUD working well, and edge discomfort at 5120x1440 borderless. The local DLAA log
confirms a 5120x1440 render/output viewport and active native HDR. Saved settings
use `r_fullscreen -2`, `g_fov 80` and the centered 16:9 HUD. The brightness report
is consistent with replacement of SSAO by a different occlusion estimate; no
new anti-aliasing or direct lighting is inferred from that observation.

Source review found an existing FOV control in Settings > Game Options, limited
to 80–100. `MenuScreen_Shell_GameOptions.cpp` now permits 60–100 with the original
five-degree step. `idGameLocal::CalcFov` already derives projection from actual
viewport dimensions every frame: at 32:9, base 80 gives approximately 118 degrees
horizontal and base 70 gives 109. No resolution-specific projection change is
needed. Edge stretching is a plausible explanation; other edge artifacts remain
unidentified. Narrowing FOV trades peripheral visibility for less stretching.

The weapon-position interpolation remains anchored to 80–100 and clamps below
80, preserving existing placement. Values apply/save when leaving Game Options;
the multiplayer minimum of 80 is unchanged. There are no resource-format,
shader, AO-strength or HDR changes. `Test-NeuralDoom-Smoke.ps1` adds explicit
borderless and base-FOV inputs to cover the actual desktop mode. Build/runtime
results follow below. Next manual check: compare 70 and 80 in the same room.

All three `RelWithDebInfo` builds pass from clean code commit `54d611a0`:

| Build | SHA256 |
|---|---|
| Native RT | `416C4E90B02F8D7748BB615E65B6597C186C582642FF7A8FF932A4FE893E264B` |
| DLAA/RT | `7F75F38D006EEC90A19D85A92E214F2AF656058089FFFC4B0555480D22CABEC9` |
| Compiled OFF | `3831A3BB4516FD7D196185CC13CC28D9FF8202E3A81EAB47A776379F23827712` |

Two focused smoke checks pass with full DX12 validation and 64 GPU samples:

- `smoke-20260906-184111-789128cd`: DLAA, `-Borderless -Width 5120 -Height 1440
  -FieldOfView 70 -RayTracedAO -DisplayOutput AutoHDR -ExpectedHDR Active`,
  600 warmup frames. Actual render/output and PNG dimensions are 5120x1440;
  HDR is active, DLAA presents with zero rejects, AO ON/OFF/ON and history reset
  pass. AO samples initially shade 1,635 receivers with 1,055 occluded. Saved
  isolated config contains `g_fov 70` and `r_fullscreen -2`.
- `smoke-20260906-184140-bc32db51`: compiled OFF, 1280x720, `-FieldOfView 60`,
  180 warmup frames. Gameplay, captures, history reset and exit pass; ray commands
  skip and AO dispatch/counters stay zero.

Public-source audit, whitespace and PowerShell syntax checks pass. Focused review
confirms unchanged default FOV, old-range weapon interpolation, viewport-based
projection and isolation from existing saved settings. The menu's expanded
range is reviewed in source; the automated scenarios set its existing `g_fov`
cvar directly. This results-only commit does not rebuild the tested binaries.

## 2026-09-06 — First gameplay ray-traced ambient occlusion

`RayTracingDiagnostic.cpp` now shares the validated static BSP extraction with a
persistent opt-in AO pass. `RenderBackend.cpp` applies it before ambient lighting;
`RenderSystem_init.cpp` clears map/device ownership. The new SM 6.5 AO shader,
resource formats, depth/normal conventions, fallbacks and controls are documented
in [RAY_TRACED_AO.md](../RAY_TRACED_AO.md). The RTX launcher requests native HDR (Auto)
and supports both Native and DLAA. No new binary dependency is tracked.

Initial Native `RelWithDebInfo` configure/build passed. The first runtime attempt
exposed NVRHI's prohibition on two simultaneously open immediate command lists.
Scene upload/build now uses an independent deferred list. A subsequent strict
coverage check sampled the closed, excluded elevator door; final checks require
shaded receivers after opening and after resize. A 600-frame warmup also provides
useful open-door comparison captures.

`smoke-20260906-180746-ddaea461` passes on RTX 5090 with full DX12 validation:
Native, 2560x720 -> 1920x1080, 600 warmup frames, 64 GPU samples, local probe
lighting, AO ON/OFF/ON. Sampled shaded/occluded receivers are 356/221 initially,
356/223 before disable and 748/487 after resize. Dispatch count holds at 781
while disabled and reaches 900 after resuming. Static AS: 82,833 triangles,
5,242,880 bytes; one build per map. Gameplay, captures, history reset and exit
pass. Initial captures were inspected; final HDR monitor appearance and moving
camera quality still require a short visual check.

Focused review covers shader binding ABI, depth agreement, immutable AS lifetime,
deferred initialization, resize rebinding, baseline SSAO retention and live
rollback. Full material registration, dynamic/cutout occluders and authored-light
ray shadows remain the next tasks.

### Final artifact checks

All three `RelWithDebInfo` builds pass from clean implementation commit
`f13d3be3`. These final executables were tested without subsequent rebuilding:

| Build | SHA256 |
|---|---|
| `build-rt` Native RT | `23A22E48DE3C70C693E3BA4EEC0122A32BA026AAFCF2E110820617701D5BC492` |
| `build-streamline` DLAA/RT | `2BC46C706E2D697DABF2CF6F0151B7176630C8DC2BB75746198261258FD85A81` |
| `build` RT compiled OFF | `5C744D1A506D6231355B06BDD4CC4C5A1C2A7D5E2E45870A6196752F65B0C66F` |

Every smoke row uses full DX12 validation, local probe lighting, 64 GPU timing
samples, history reset and normal exit. AO rows include live OFF/ON comparison
and 600 warmup frames; compiled OFF uses 180 warmup frames.

| Artifact under ignored `captures/neural` | Scenario | Result |
|---|---|---|
| `smoke-20260906-181359-47661d1b` | Native AO + synthetic ray checks, 2560x720 -> 1920x1080 | PASS: both 24-ray checks; shaded/occluded samples 350/220 initially and 741/487 after resize; frames stop at 782 while disabled |
| `smoke-20260906-181424-fd99b123` | DLAA AO + native HDR, 4800x1350 -> 2560x720, HUD aspect 1.777778 | PASS: 1,232/797 shaded/occluded samples initially, 354/223 after resize; frames stop at 781 while disabled; DLAA presentation has zero rejection |
| `smoke-20260906-181910-b778744e` | Compiled OFF, 2560x720 -> 1920x1080 | PASS: ray diagnostics skip; AO frames/counters remain zero; raster rendering and resize pass |
| `ao-lifecycle-final` | Native AO, two consecutive Mars City 2 loads, 1280x720 | PASS: exactly two static AS builds, dispatch counters restart at each load, both scenes shade and exit normally |

Windows HDR was enabled for this test. The DLAA run confirms
`windowsHDR=1`, `active=1`, scRGB FP16 and 10-bit display metadata. Actual HDR
transport is tested with `diagnostic=0`: scRGB maxima are 11.046875/11.734375
before resize and 10.0 afterward, below the configured 12.5 scRGB / 1,000-nit
ceiling. Presentation has zero invalid or negative values. Intermediate DLAA
composition has negative overshoot after resize; the final presentation clamps
it. Monitor brightness, artistic quality and motion artifacts remain manual.

Eleven final smoke PNGs pass CRC/decompression checks; Native ON/OFF and resized
DLAA/HDR previews were inspected. Both RTX launcher profiles pass exact-artifact,
SDK-file and map-data validation. The default-build runner initially hit a
PowerShell StrictMode error when its failure-filter returned no rows; wrapping
that filter in an array fixed reporting, and the final rerun passes. A debug-event
wrapper exceeded its 60-second budget during the second map load; the equivalent
unwrapped two-load run passes with full DX12 validation retained.

The follow-up changes only that test-reporting fix and documentation. Build
manifests retain the clean implementation commit above; no renderer/shader or
executable changed after the final checks. Public-source/whitespace checks and
PowerShell syntax validation pass. The five-minute dogfood checklist is ready.

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
- Pending: exercise a fresh 2 GB ModDB download/mirror redirect and a fresh NR file/URL copy in a disposable clean install. Neither path was forced against the existing test installation during this validation.

## 2026-09-03 / ND3-350 / engine-owned compatibility startup

- `RelWithDebInfo`, Streamline-enabled: PASS. Reconfigured `build-streamline` after adding the renderer source and built/staged `neuralDoom.exe` successfully (19,845,120 bytes; SHA-256 `FE2944D2B4EC0536FF846B1BB47A86FDDFC740864E636D128540C34D9FB07DFD`).
- `RelWithDebInfo`, SDK-OFF: PASS. Reconfigured `build` and built the default executable successfully; the compatibility loader has no link-time ReShade dependency and defaults disabled.
- Reversible local mode switch: PASS. The helper moved the ignored `dxgi.dll` to `neuraldoom-reshade64.dll` and left no proxy DLL beside the executable.
- Embedded startup probe: PASS. `ReShade.log` identifies ReShade 6.8.0.2155 as loaded from `neuraldoom-reshade64.dll`; DLSS5 add-on version `0.2026.828.2110` registered with API 18; the local NR runtime was preloaded at device init; a ReShade runtime was created on the test GPU at 1280x720.
- Gameplay/visual parity with the earlier feature-18 pass: PASS. Manual playtesting launched the embedded NR + D3HDP profile and confirmed that the NR path and F6 behavior still work in gameplay.

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

- None observed in the automated feature-off smoke. Full visual D3HDP/NR quality validation remains manual acceptance.

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
| Project-priority review | DEFERRED | This checkpoint prioritizes native-resolution reconstruction quality. Quality mode remains an infrastructure diagnostic; the planned NR path should normally retain 100% source resolution. |

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
| T15 map/save-load signal | PASS | scripted map load, test save resume, and `neuralHistoryStatus` | First tracked view consumed `initialization|level-load|framebuffer-resize`; resumed gameplay rendered normally without stale feedback. |
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

- Validation: Windows runtime checked manually.
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

- Validation: Windows runtime checked manually.
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

- Validation: Windows runtime checked manually.
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

- Validation: Windows runtime checked manually.
- Branch and base commit: `feature/neural-rendering-spike`, `c9c5e063`.
- Build configuration: `RelWithDebInfo`, VS2022 x64, DX12 only.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Scene/save/map: resumable test save in Mars City Hangar with a visible moving rigid object.
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

- Validation: Windows runtime checked manually.
- Branch and base commit: `feature/neural-rendering-spike`, `d6d361fa`.
- Build configuration: `RelWithDebInfo`, VS2022 x64.
- CMake options: established DX12-only configuration.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Resolution / HDR / AA: runtime tests at the current window size; validation capture at 1725x985; `_taaMotionVectors` is `R16G16_FLOAT`; TAA active.
- Scene/save/map: resumable test save in Mars City Hangar.
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

- Validation: Windows runtime checked manually.
- Branch and base commit: `feature/neural-rendering-spike`, `992b6355`.
- Build configuration: `RelWithDebInfo`, VS2022 x64.
- CMake options: `FFMPEG=OFF`, `BINKDEC=ON`, `USE_DX12=ON`, `USE_VULKAN=OFF`; established `/wd4530` and Windows SDK DXC overrides.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Resolution / HDR / AA: 1280x720 validation capture; output resource `R8G8B8A8_UNORM`; TAA active.
- Scene/save/map: resumable test save in Mars City Hangar.
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

- Validation: Windows runtime checked manually.
- Branch and commit: `feature/neural-rendering-spike`, upstream `ea29c006e84fedcc0e7c173c383a087ce0a8c0d5` plus documentation/helper changes.
- Build configuration: `RelWithDebInfo`, VS2022 x64.
- CMake options: `FFMPEG=OFF`, `BINKDEC=ON`, `USE_DX12=ON`, `USE_VULKAN=OFF`; local `/wd4530` compatibility flag; Windows SDK DXC override.
- GPU and driver: NVIDIA GeForce RTX 5090, 610.47.
- Resolution / HDR / AA: 1280x720 capture; `R16G16B16A16_FLOAT` HDR scene; single-sample depth/motion/LDR; TAA pass active.
- Scene/save/map: resumable test save in Mars City Hangar.
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
- Git uses the configured downstream origin and the RBDOOM-3-BFG upstream. Publication is separate from this validation checkpoint. No proprietary payloads are included in the source checkpoint.
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
sequence extended. It did not drive an active game or its configuration.
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

## 2026-09-06 - Probe lighting repair and native ray-tracing readiness

Checkpoint: `codex/probe-lighting`, based on `5ca342cf`; next working branch
`codex/rt-foundation`. This implements diagnostics and an empty-grid loading fix,
not a ray-tracing pass. See `PROBE_LIGHTING.md` and `RAY_TRACING_PLAN.md`.

### Changes and content provenance

- `RenderWorld_envprobes.cpp::probeLightingStatus`: on-demand world/probe/grid
  counts and current view selection, including defaulted images and positive-weight
  fallback slots. No textures are allocated or reloaded by the command.
- `RenderWorld_lightgrid.cpp::LoadLightGridImages`: use the baker's existing
  `CountValidGridPoints() == 0` condition to skip nonexistent atlases for empty
  areas. Leave their image pointers null for the existing frontend probe fallback.
  Missing images in populated areas still take the normal warning/fallback path.
- `RenderSystem_init.cpp::R_RayTracingStatus_f/R_InitCommands`: read-only NVRHI
  acceleration-structure, pipeline and inline-query capability report, explicitly
  separate from `sceneImplemented=0`.
- `Test-NeuralDoom-Smoke.ps1`: record these diagnostics, assert the expected loaded
  map and optional Local/Fallback probe state. `Get-NeuralLightingData.ps1`, setup
  and prerequisites report absent lighting candidates without claiming that a
  filename inventory proves map coverage.
- No shader, texture format, coordinate convention, default lighting cvar or SDK
  dependency changed. Loaded bake formats remain the existing HDR probe/BC6 path.
- The official v1.6.0 lighting pack was extracted alone and installed locally.
  All 12,244 ZIP entries passed CRC checks and path/type inspection. Its 12,150
  images include all 196 exact missing Mars City 2 probe names, plus light grids.
  Archive/pack SHA-256 fingerprints are recorded in `PROBE_LIGHTING.md`. Nothing
  from the release's executables/shaders or retail/runtime payloads was staged in Git.

### Builds and runtime

Configured both existing DX12 build trees with `Configure-RBDOOM-DX12.ps1`, then
built `RelWithDebInfo` using `Build-RBDOOM.ps1 -BuildDirectory build` and
`-BuildDirectory build-streamline`: PASS. SDK remains OFF in the default build.
Final tested executable SHA-256:

- SDK-OFF: `17C1A71291521C04AC4E05422EBF66262B734605DDA7006A3BC4085FBB82687E`.
- SDK-ON: `18AA22E824ECE548174C4885B73A99023E7AE52DDCD8CC74E602AA27A9BD3A0F`.

Runtime manifests retain the parent commit and dirty=true while these changes
were under validation. Final synchronization refreshes manifests and checks that
committing did not substitute a different executable. The root launcher executable
was not replaced.

All artifact directories below are under the game checkout's ignored
`captures/neural`. Runs use `game/mars_city2`, SDR, bridge disabled, isolated configs,
600 warmup frames and existing fixed-tick GPU profiling. No user playtest was needed.

| Artifact | Scenario | Evidence |
|---|---|---|
| `smoke-20260906-135818-d546a429` | Initial diagnostic, Native 2560x720, missing pack | PASS; 98 probes, zero ready pairs, 196 defaulted textures; loaded placeholders are not real bakes |
| `smoke-20260906-140042-e1fb87ec` | Added grid diagnostic, Native 2560x720, missing pack | PASS Fallback assertion; no grid images; 392 repeated probe-image warning lines represent 196 unique images |
| `smoke-20260906-140416-c551e2de` | Pack restored, before empty-grid loader fix, Native 2560x720 | PASS Local assertion; 98 pairs and 93 grids load; 22 repeated warning lines for 11 empty grids identify the loader mismatch |
| `smoke-20260906-140826-6b790263` | Final SDK-OFF Native 2560x720, 64 GPU samples | PASS; 98 pairs, 93 grids, 11 empty areas, zero defaulted/populated-missing images and zero lighting-image warnings |
| `smoke-20260906-140851-72659aec` | Final SDK-OFF Native 4800x1350, 300 GPU samples | PASS; same lighting coverage; median GPU 1.569296 ms, p95 1.588288 ms |
| `smoke-20260906-140922-522c1817` | Final SDK-ON DLAA 4800x1350, 300 GPU samples | PASS; same lighting coverage; evaluated/presented with zero rejection; median GPU 2.021728 ms, p95 2.044736 ms |

Every completed scenario passed primary-view progress, history reset, expected
backend state and screenshot dimensions. Startup `probeLightingStatus` safely
reported `world=0`. The final selected view has local diffuse and two local
specular slots; its remaining default slot has zero blend weight. The script
checks active fallback contribution rather than mistaking an unused slot for a
missing bake.

All six final PNGs passed chunk CRC, full pixel-stream decompression, dimensions
and scanline-filter validation. The 2560x720 missing-pack, restored-pack and final
captures were visually inspected: recognizable geometry, lighting, weapon and HUD,
with changed ambient/reflection shading after pack restoration. This is one still
view, not motion/ghosting acceptance or a claim about every map's appearance.
The 4800x1350 captures received structural validation; no full-size perceptual
DLAA comparison is claimed. Timing is one scene, not FPS or a broad performance
gain. The smaller missing-pack run has the previously observed clock-sensitive
GPU timing behavior and is not suitable for a before/after speedup claim.

### RTX readiness and focused review

The actual DX12 device reports acceleration structures, ray-tracing pipelines and
inline ray queries supported on RTX 5090 / NVIDIA 610.47. Windows SDK 10.0.26100.0
DXC compiled an isolated `RayQuery` compute shader using `-T cs_6_5 -E main -WX
-Zpr` (3,532-byte DXIL, local ignored artifact). This is capability/compiler proof
only; no acceleration structure or ray dispatch was implemented or tested.

Focused review covered game-thread synchronization, null/no-world diagnostics,
loaded-versus-defaulted reporting, zero-weight specular fallback, zero-point and
invalid-only grids, preserved missing-valid-grid warnings, no per-frame scanning,
and unchanged SDK-OFF/backend paths. The parser was exercised against actual
missing and restored data; inventory reported both absence and presence correctly.
PowerShell syntax/build-identity checks and whitespace/source audits pass.

Next: RT-001's OFF-by-default synthetic-triangle hit/miss readback and static-map
scene audit. Broader map/mod compatibility, moving lighting, denoiser selection and
real HDR display calibration remain separate work. No path-tracing image-quality
or frame-rate claim is established by this checkpoint.

## 2026-09-06 - Native DXR intersections and presentation lifetime fixes

RT-001A / ND3-661 on `codex/rt-foundation`, based on `5fab1f08`. The planned scope included
continued unattended development and a concise later playtest. See
`RAY_TRACING_DIAGNOSTICS.md` for the resource contract and `TEST_PLAN.md`
for the manual pass. This checkpoint adds on-demand GPU diagnostics, not gameplay
ray-traced lighting or a persistent RT scene.

### Source and build

- `RayTracingDiagnostic.cpp::RayQueryDiagnostic`, `TestSynthetic` and
  `TestStaticWorld`: owned vertex/index/AS resources, compute pipeline, GPU timing,
  readback and independent CPU reference tests. Positions are float3 world units,
  copied indices uint32, instance transforms row-major 3x4, input/output strides
  48/16 bytes. No temporal/HDR texture format or motion convention changed.
- `neo/CMakeLists.txt`, `neo/shaders/CMakeLists.txt` and
  `neo/shaders/rt/ray_query.cs.hlsl`: `USE_RAYTRACING=OFF` default, DX12/DXIL gate,
  standalone SM 6.5 compute target with warnings as errors. Existing SM 6.0 shaders
  and SDK-OFF remain supported. `rayTracingStatus` identifies compiled diagnostics
  separately from the still-unimplemented gameplay scene.
- `neo/cmake/NvrhiRayTracingFix.cmake`: a reproducible two-line correction applied
  to a build-tree copy of pinned NVRHI's ray-tracing translation unit. Original
  submodule contents remain unchanged. Both RT build projects compile that copy;
  the default build uses the original source. The patch preserves MIT notices.
- `DeviceManager_DX12.cpp::ReleaseRenderTargets/DestroyDeviceAndSwapChain`: submit
  an empty NVRHI graphics command list after external Present work, then wait for
  its fence before freeing DXGI buffers. NVRHI's previous last-submission fence
  could precede Present. The extra synchronization occurs at release/resize,
  without adding a per-frame wait.
- Configure/build helpers record the RT option. The smoke runner adds synthetic,
  scene, disabled and missing-shader modes plus explicit validation level. The
  playtest launcher verifies build SHA/configuration/features, selects Native or
  DLAA and shares persistent isolated settings without overriding later HUD,
  resolution or HDR choices. No retail data or vendor runtime enters Git.

Configured with `Configure-RBDOOM-DX12.ps1 -BuildDirectory <tree> -RayTracing
ON|OFF`, built with `Build-RBDOOM.ps1 -BuildDirectory <tree> -Configuration
RelWithDebInfo`. All three PASS; existing official Streamline 2.12.0 supplies the
optional DLAA build. No new SDK was acquired. Final tested executable SHA-256:

| Build tree | SDK / RT | SHA-256 |
|---|---|---|
| `build` | OFF / OFF | `BBBFF8101E1F5A42C332A8AC612BEE19945CAAF08B68E463427667C45D4E1C80` |
| `build-rt` | OFF / ON | `FBE6B9D5D7A6FFD60E5088EEE851CC35D583F793A6FBDF1C7D87805B56C85F0B` |
| `build-streamline` | ON / ON | `F5CEA4C225BAFB5D887AFB85E8375D36A02675CEE0761046466F74BEA6563FC5` |

The initial run manifests retain the parent commit and dirty=true from validation.
The post-commit incremental link changed both RT-enabled executable hashes, which
the identity check caught. The exact final files listed above were tested again
at clean code commit `a65128be`, as recorded below. The default build hash stayed
unchanged. The dogfood launcher selects these exact build-directory targets.

### Failures found and repaired

Initial NVRHI-only runs passed synthetic, world and missing-shader checks.
`smoke-20260906-144211-ac731a8e` with `-ValidationLayers 2` failed with exit 2170.
A bounded debugger capture, `debug-rt-20260906-144540`, identified native DX12
message 1162: uninitialized `DescsLayout` in the TLAS prebuild descriptor. Storage
initialization and explicit `D3D12_ELEMENTS_LAYOUT_ARRAY` fix the initial build
and the instance-update path. BLAS still uses its explicit pointer-array layout.

With that corrected, `debug-rt-20260906-144649` passed the ray checks but failed
on resize with DX12 message 921, `OBJECT_DELETED_WHILE_STILL_IN_USE`, naming
`SwapChainBuffer`. The same resize failed in the RT-OFF build
(`smoke-20260906-144820-ab645b68`). The post-Present fence fixed this independent
presentation-lifetime bug. Debugger helper output also encountered a console
encoding error while printing its retained log; the DX12 messages were recovered
from that file. All final native-debug smoke scenarios below complete normally.

### Final unattended runtime evidence

Artifacts are under the game checkout's ignored `captures/neural`, using
`game/mars_city2`, RTX 5090 / NVIDIA 610.47, bridge OFF and isolated settings.
Every row uses `-ValidationLayers 2 -ExpectedProbeLighting Local -GpuProfile`.
The Native rows use 180 warmup frames and 64 GPU samples; DLAA uses 600 and 300.

| Artifact | Scenario | Result |
|---|---|---|
| `smoke-20260906-145700-355f7385` | Native RT Scene, SDR 2560x720 -> 1920x1080 | PASS: three 24-ray synthetic tests, world/CPU comparison, resize/history reset and clean exit |
| `smoke-20260906-145717-1e5a763d` | DLAA RT Scene, AutoHDR + HDR diagnostic, 4800x1350 -> 2560x720, HUD aspect 1.777778 | PASS: same ray checks, native DLAA evaluated/presented with zero rejection, finite FP16 composition and scRGB presentation, resize/history reset and SDR-desktop bounds |
| `smoke-20260906-145747-0c74bf55` | Default RT-OFF build, BuildDisabled, SDR 2560x720 -> 1920x1080 | PASS: both RT commands skip and no RT build/trace work occurs; resize and normal rendering continue |
| `smoke-20260906-145814-74403766` | Native RT build, MissingShader, SDR 2560x720 | PASS: empty bytecode in the run's own filesystem overlay produces the expected contained diagnostic failure before GPU work; gameplay/captures/reset continue |

Both scene runs audit 104 BSP models, 2,237 included surfaces and 772 excluded
surfaces: 87,848 positions and 82,833 triangles. Of 131,072 panorama rays, 130,777
hit, including 65,536 behind-camera hits. All 32 CPU closest-distance samples
agree; invalid-hit count is zero. The scene uses 5,242,880 bytes of AS allocations.
Native one-shot GPU build/trace were 0.490656/0.018560 ms; DLAA run values were
0.484640/0.013920 ms. These exclude CPU work and are diagnostic measurements under
validation, not gameplay performance or path-tracing estimates.

All final runs retain 98 complete local probe pairs, 93 populated grids, 11 empty
areas, no active probe fallback and zero lighting-image warnings. Existing
content/startup warnings remain. Thirteen final PNGs pass chunk CRC, full pixel
stream decompression, dimensions and scanline-filter checks. The Native gameplay
capture and a 360-degree depth panorama were visually inspected. No motion-quality
or real HDR monitor acceptance is inferred from these still images; Windows HDR
remains OFF. The DLAA HDR diagnostic is a transport test, not a normal art capture.

### Review and next gate

Focused review covered shader ABI, masks/transforms and closest-hit semantics,
BLAS/TLAS update flags, queue barriers and ownership, all-area map enumeration,
geometry limits, no-world and feature-OFF behavior, isolated failure injection,
submodule reproducibility and Present ordering. Exact-build fixtures and all
PowerShell syntax pass; both dogfood profiles pass manifest/runtime/data checks
with `-ValidateOnly`. Whitespace and public-source checks precede the commit.

RT-001B remains: persistent mesh/instance registration and material mapping, map
lifetime rebuild/release, then moving/skinned/cutout geometry and one selected
light's ray-traced visibility. Actual unsupported hardware, invalid-shader/device
loss recovery, other maps/mods and full path tracing remain unverified. The manual
playtest focuses on ultrawide HUD behavior, motion, lighting, saved settings and
optional real HDR calibration.

### Post-commit artifact verification

Clean code commit `a65128be` was built in all three configurations. The initial
RT-ON hashes were `27676C85FC0810C2908436EF76F43935F347E13E9F1D5EEB2CAEC8968E4F611A`
(Native) and `361602AB6BBAA17F16AEEFB0B80ED1521166497764CD3727F978EE50BE70EEC3`
(DLAA); the incremental link replaced them with the final hashes in the build
table. No source changes were made during this verification.

| Artifact | Repeated final-file scenario | Result |
|---|---|---|
| `smoke-20260906-150810-dabb8e80` | Native Scene, full DX12 validation, 2560x720 -> 1920x1080 | PASS: synthetic/world reference checks, local lighting, reset, resize and normal exit |
| `smoke-20260906-150828-9d59f27c` | DLAA Scene, full DX12 validation, AutoHDR diagnostic, 4800x1350 -> 2560x720 | PASS: ray checks, DLAA presentation, finite HDR transport, SDR desktop bounds and resize |
| `smoke-20260906-150859-2d05a02d` | Native MissingShader, full DX12 validation, 2560x720 | PASS: contained missing-bytecode failure followed by normal gameplay |

The same parameters as the corresponding earlier rows were used. Ten additional
PNGs passed CRC, decompression, dimensions and filter checks. Final manifests
record clean code commit `a65128be`; this later results-only documentation update
does not require rebuilding the already tested executables.


## 2026-09-07 — Settings and exposure review

Configured each existing tree using `Configure-RBDOOM-DX12.ps1 -RepoRoot <game> -BuildDirectory <tree>` and built with `Build-RBDOOM.ps1 -RepoRoot <game> -BuildDirectory <tree> -Configuration RelWithDebInfo`: PASS for native RT, official Streamline RT and SDK/RT-off baseline. No shaders or resource formats changed. Exact output hashes:

| Tree | SHA-256 | Shader files |
|---|---|---:|
| build-rt | `321EE046B5B69B81D28A8DE68485AA4888730A05DD231E2950A8A7DB7E5D5EB3` | 151 |
| build-streamline | `B9AA6ED309F638B20A32898F1CE3B2E2A9E29CE083FD3547BABCA458A7F1C7CE` | 151 |
| build | `687B550A97528D5AF05E354997969416533765E109DBE05324A851A141D6228B` | 141 |

`Test-NeuralBuildIdentity.ps1`: PASS (exact-target selection, stale-output rejection, configuration isolation, safe-clean and PowerShell syntax fixtures). `git diff --check`: PASS. Focused code review checked fixed/automatic branches, first-use exposure initialization, bounded elapsed-time adaptation, live DLSS exposure-option refresh, SDK-off compilation, archived-setting precedence and SSR material selection. Build logs are ignored local `captures/neural/settings-{configure,build}-<tree>.log` files.

No gameplay, GPU capture or visual comparison performed. Visual acceptance requires manual testing. Auto-exposure off now changes the formerly incorrect adaptive behavior; dark rooms can become considerably darker. DLAA/native luminance equivalence is not established. See SETTINGS_REVIEW.md for the one-time preset and focused checks. No SDK or private NR dependency was added.


## 2026-09-07 — User DLAA settings-menu crash and preference reset

A playtest reported an access violation while in settings, on the DLAA launch route. Windows Application Error 1000 identifies engine fault RVA `0x5363c3`; resolving against the matching RelWithDebInfo executable/PDB through DbgHelp gives `idSWFScriptObject::GetVariable(const char*, bool) + 0x63`, `neo/swf/SWF_ScriptObject.cpp:526`. The log includes `slSetConstants: eErrorDuplicatedConstants` with native TAA fallback earlier; causality is not established. No crash dump was found in the inspected locations. A symbol address without a call stack does not establish the underlying menu/object-lifetime defect. No speculative renderer or SWF fix applied.

Backed up and removed active shared `D3BFGConfig.cfg` and generated `neural_dogfood.cfg`; no migration marker existed. Reset the local NR tuning section to addon defaults with enable/full-resolution safeguards retained. Saved games, logs, prior backups and runtime components are preserved. Existing launchers share this preference directory. All game preferences, including HDR calibration and key bindings, will regenerate; automatic contrast migration remains pending for next normal launch. No game launched. Next investigation needs the exact settings action or a captured crash stack; preference reset alone is not evidence that the crash is fixed.


## 2026-09-07 — Menu hover lifetime regression

`Test-SWFHoverLifetime.py` compiled the actual `idSWF::HandleEvent` mouse-hover block with MSVC against reference-count fixtures: PASS for removed next target, repeated same target, empty space, reentrant roll-out and balanced references. The identical test against pre-fix `SWF_Events.cpp` fails with `retain after free`, establishing a real regression rather than a source-text assertion. Matching-binary disassembly confirms the reported fault is the initial object dereference, not the later hash-chain bounds workaround; that unrelated workaround was not modified.

`Configure-RBDOOM-DX12.ps1` then `Build-RBDOOM.ps1 -Configuration RelWithDebInfo` passed for all three existing trees. Focused diff review and `git diff --check` passed. No renderer settings, shaders, SDKs or formats changed. No game launched; exact reproduction of the reported menu crash remains pending because no stack/dump or exact input sequence was available.

| Tree | Executable SHA-256 |
|---|---|
| build-rt | `DB66CB4B1DAEF929088E554268445CB38739D9AE61ACA8815A6F43220F220F68` |
| build-streamline | `A46EDE1280006F4E158CFCAA1CF8EE757DD486B1AB432FCB5A5CD485662BE148` |
| build | `7ADECFF9B9AA71C32E65518E0FAAB95687D9D8FFD242BBCD3263D310D4BABC1C` |


## 2026-09-07 - Graphics controls and dynamic ray geometry

Configured and built RelWithDebInfo for `build` (SDK/RT off), `build-rt` (RT on, SDK off) and `build-streamline` (RT/official SDK on) using `Configure-RBDOOM-DX12.ps1` and `Build-RBDOOM.ps1 -Configuration RelWithDebInfo`: PASS. Final incremental rebuild after review: PASS. No dependencies changed.

- `Test-DynamicRayGeometry.py`: PASS actual CPU source fixtures for global vertex offsets, per-surface UV/material IDs, shadow policy, limits, invalid/empty/disabled geometry, rigid world transforms, current weighted skin pose, immutable copies and bad joint/index rejection.
- `Test-SystemOptionsSelection.py`: PASS 264 scrolled selections plus empty/out-of-range commands. Mouse/controller visual navigation remains user validation.
- `Test-NeuralEmbeddedNR.ps1`: PASS saved TAA/DLAA selection, NR DLAA input isolation, saved RTX off choices, missing-preference seeding and existing one-time migration/backup checks. No NR process launched.
- `Test-ReflectionShaderContract.py`: PASS all 64 exact capture/baseline shader permutations and compute constant-buffer contracts.
- Isolated DX12 validation-layer DLAA smoke at **5120x1440 borderless**, all four RTX effects enabled: PASS. `RT_DYNAMIC_TEST status=PASS phases=4 mismatches=0` proves insertion, motion, no-shadow filtering and removal via GPU ray queries. Gameplay included 39 dynamic surfaces / 3568 triangles / 5 skinned surfaces with zero backend budget skips. Reflection output remained 5120x1440 with `fullResolution=1`; contact/GI/reflection sampled invalid counts were zero. All eight off/on toggles advanced history with lighting-change reasons, and gameplay exited normally.
- Isolated native SDK/RT-off smoke with 1280x720 to 1920x1080 resize: PASS, no gameplay ray dispatch, valid history reset and normal exit.
- Focused source/diff review and `git diff --check`: PASS. Public-source audit passed; staged audit repeated for new files before commit.

Evidence is kept locally under `captures/neural/final-dlaa-borderless-smoke.log`, `final-baseline-smoke.log`, `final-launcher-tests.log` and `checkpoint-*.log`. Early smoke assertions incorrectly expected renderer-thread Printf output in the Windows file log; tests now query actual history state. A windowed 5120x1440 request produced a 5120x1421 client area because of window chrome; the full-size borderless rerun passed. Neither issue was a renderer resolution reduction. The final telemetry-only review fix avoids briefly publishing Native while a DLAA evaluation is in progress; it was rebuilt after GPU runs and does not alter shading.

| Final tree | Executable SHA-256 |
|---|---|
| build-streamline | `1F3B864C2B904AC095DDDE4DAAF8AFDD1834F0B01BCD77727FF1C2E5EC769513` |
| build-rt | `5EE3E982F5FA3475A5DBD95D3DD5DCBC7490C2F3A53E67D204E7D88DEF32B8A2` |
| build | `9192B68133D40D9C3E0DF1BA5D09ED579093C315D37C59664ED6914EB2F8D112` |

No user preference/saved-game resets. Appearance, live menu TAA/DLAA switching and real door/character comparisons remain manual playtest checks. Known limitations: visible-only opaque dynamic geometry, bounded budgets and suspended reflection temporal accumulation while dynamic surfaces are present. Next task: use visual feedback to prioritize off-screen dynamic coverage and secondary-hit history, then profile BLAS cost.


## 2026-09-07 - Internal controls and Release readiness

Native RTX `Release` and all three existing `RelWithDebInfo` configurations built successfully. Import inspection identified debug CRT dependencies in the development configuration; the new Release EXE imports the normal VC++ runtime and Windows DLLs, with no NVIDIA runtime imports. Release SHA-256: `5D8F50B52F8C3131E404A8480519DED075DF9DA90B9081FF027E9417BB4D3BD9`.

`Test-InternalControls.py` executes the actual safe-key migration against custom bindings, legacy F6/F9 conflicts, first-use/idempotent startup and intentional unbinding: PASS. It also checks default-key commands exist and F5/F9/F12 remain unchanged. The menu selection fixture passes 264 scrolled selections. Launcher fixtures pass saved profile selection without prompts, preference preservation, safe NR key preparation and one-time contrast migration.

The native RTX Release GPU smoke passed with validation enabled, all four features, synthetic/dynamic ray tests, safe key startup and all eight transitions through the new named bindable lighting commands. Temporal epochs advanced correctly; sampled invalid lighting values were zero; exit 0. Evidence: `captures/neural/internal-release-smoke-final.log`. An initial run caught a semicolon inside a CFG comment being interpreted as a command separator; the comment was corrected and the complete smoke rerun passed. Renderer output formats/resolution are unchanged.

Package relocation, installer and exported-game validation are recorded in the follow-up package checkpoint. Visual menu navigation and external fresh-machine acceptance remain pending.


## 2026-09-07 - Exported installer and relocated Release validation

Built the allowlisted source/native-Release ZIP from clean matching source/build commit `86e0dd07`. It contained 2841 files, approximately 28 MiB, with no DLLs, PDBs, retail resources or PK4s. Included shader entries cover both ShaderMake `.bin` permutation containers and standalone `.dxil` ray shaders. ZIP CRC checks, SHA-256 sidecar generation and full extracted-file verification passed.

Ran `Install-InternalTest.ps1 -NonInteractive` in a newly extracted folder with locally owned BFG data and the verified lighting pack: PASS. The installer rebased the manifest/artifact paths and the existing exact-build/shader/lighting readiness checks passed without Git or a compiler in the installation folder. No game started during installation. `Test-InternalPackage.ps1` then verified shader tampering and path escape rejection, restoring the original bytes and re-verifying all files: PASS.

Ran `Test-NeuralDoom-Smoke.ps1 -Configuration Release -Profile Native -RayTracingDiagnostics Synthetic -RayTracedAO -RayTracedContactShadows -RayTracedGI -RayTracedReflections -ResizeWidth 1920 -ResizeHeight 1080` against the extracted installed EXE and its own data/shaders, with validation enabled: PASS, exit 0, all named lighting toggles/reset epochs valid, dynamic GPU test passed, full-resolution reflection output and zero sampled invalid lighting values. Evidence: `captures/neural/internal-install-test.log`, `internal-package-tests.log`, and `internal-installed-smoke.log`. This verifies relocation on the development machine, not a different GPU/driver or untouched Windows installation.

The final package refresh includes this record and the package regression script; engine/shader bytes are unchanged from the tested Release. Local Native, DLAA and NR launch validation is repeated after final manifest refresh. No package was uploaded or sent, and no private runtime or retail data entered the ZIP. External menu/visual tests and fresh-machine acceptance remain the next step.


## 2026-09-07 - Automatic dependency acquisition and setup bootstrap

`Get-SetupLightingPack` successfully downloaded the actual 1,647,091,125-byte official RBDOOM release and pinned 7zr 26.03 executable into an isolated cache, extracted only `base/_rbdoom_global_illumination_data.pk4`, and verified its recorded SHA-256/size. No game ran and no archive content was bundled into our package. Evidence: `captures/neural/setup-live-download.log`.

`Test-SetupDependencies.ps1` passes under Windows PowerShell 5.1 for BITS-to-web fallback, transient retries, valid cache reuse, HTTP rejection, corrupt hash rejection, non-Microsoft signer rejection before execution, and restart-required handling with a mocked process. The Microsoft installer was not executed because the development machine already has the runtime. Runtime detection checks the minimum 14.43 version as well as DLL presence.

`Bootstrap-InternalSetup.ps1 -ExtractOnly` successfully verifies and expands a real package under Windows PowerShell 5.1. A trial one-file .NET bootstrap compiled and passed `--verify` (temporary extraction plus payload SHA verification, no installation). The source-matching final EXE and integrated installation are checked at the following checkpoint. No renderer/shader modifications or GPU tests are required for these setup-only changes.


## 2026-09-07 - Automatic installer integration passed

The complete `fc5d2fd8` package compiled into a single Windows x64 .NET setup EXE; its embedded payload self-verification passed. The bootstrap sources are extracted from and hash-matched to the included source archive before compilation, avoiding checkout line-ending differences. Windows PowerShell 5.1 installed the extracted package without a LightingPackPath: it verified cached publisher archives from the successful live-download test, extracted/verified the lighting pack, imported owned BFG data and passed exact Release/shader/lighting readiness checks. Desktop shortcut creation was suppressed for this automated test to avoid changing desktop shortcuts; no game was launched. Evidence: `captures/neural/automatic-installer-integration.log`. Source engine/shader bytes remain unchanged from the previously GPU-tested Release.

The offline dependency suite also covers Steam path detection with a registry fixture. The final setup refresh includes these test records; `--verify` is repeated on its final EXE. Actual first-time VC++ installation/UAC and external fresh-machine interactive acceptance remain pending; signature rejection and installer exit handling were tested with mocked processes. Public archive download and real extraction were tested live. No third-party payload is bundled or committed. Final EXE/ZIP hashes accompany the artifacts.
# Installer destination and workspace cleanup — 2026-09-07

`Bootstrap-InternalSetup.ps1` now asks interactive setup users to choose/create an
empty destination before extraction. Explicit destinations and noninteractive
versioned defaults remain supported. Cancellation happens before extraction;
existing unrelated nonempty destinations remain rejected. No renderer changed.

Windows PowerShell 5.1 extraction of the verified package into an explicitly
selected separate test directory passed. PowerShell parsing and `git diff
--check` passed. The interactive folder picker awaits manual installer acceptance;
no game was launched. See `WORKSPACE_LAYOUT.md` for the source, release, evidence,
and ignored local archive layout.


## Graphical setup wizard — 2026-09-07

`InternalSetup.cs` now provides a Windows Forms wizard, a hidden asynchronous
PowerShell worker, stage progress/details, persistent setup logs, cancellation
at safe operation boundaries, retry, folder preflight, Steam detection and
completion links. `Build-InternalSetup.ps1` compiles a Windows GUI executable
from the hash-verified packaged source and checks its embedded payload via
`--verify`. No new third-party UI runtime was added. Bootstrap and installer
scripts accept shortcut options; the installer creates a per-user Start menu
entry. `Setup-Dependencies.ps1` reports stages and checks cancellation.

Validation: all six wizard pages rendered; a navigation overlap found in the
first rendering was fixed and re-rendered. `Test-InternalSetupWizard.ps1`
exercised the real background process/output/UI handoff with harmless success
and failure workers; both completion pages and saved logs passed. Existing
download/signature/Steam fixtures passed under Windows PowerShell 5.1.
The native Release configured and built directly in the primary source checkout
(`Configure-RBDOOM-DX12.ps1 -RayTracing ON`, then `Build-RBDOOM.ps1
-Configuration Release`); there were no renderer changes or GPU runs.
Evidence is under `captures/neural/wizard-*`.

Limits: progress reports actual stages with an indeterminate bar, not a guessed
overall percentage. Cancellation waits for the current operation (including a
large transfer) and preserves downloads; it does not roll back an installed
Microsoft prerequisite. A real missing-runtime UAC flow and an end-to-end
wizard installation remain acceptance tests. No game launches automatically.


## Public documentation and artifact privacy — 2026-09-07

The shared checklist, checkpoint and planning notes now use general contributor
and playtest instructions. Removed account references, personal scheduling and
login notes, saved display-calibration values and local archive descriptions.
Original notes remain only in ignored private reference storage. Technical
validation results, limitations and license attribution are retained.

`Test-NeuralDoom-PublicSource.ps1` now checks profile paths regardless of case
or separator and inspects staged text independently of the working copy.
Findings report file/line only. `Build-InternalPackage.py` checks every payload
entry for ASCII/UTF-16 personal profile paths and accepts an explicit native
build directory. `Test-PublicPrivacy.py` passed the corresponding negative and
placeholder/staged-content fixtures. The staged fixture caught a PowerShell
argument-quoting issue in the initial regex; a simpler expression fixed it.

A fresh native Release built using a neutral temporary drive mapping instead
of a personal source path. Inspection of the resulting executable found no
personal profile paths, including ISPC assertion strings. No renderer sources,
shader algorithms or output formats changed, and no game was launched. The
refreshed package must pass the same privacy gate and setup payload verification
before handoff. Existing Git history has not been rewritten.
# 2026-09-07 - Installer management and DLSS preset validation

- Native SDK-OFF Release and SDK-ON Release/RelWithDebInfo builds succeeded using
  `Build-RBDOOM.ps1` from a neutral mapped build path. Both retain DX12/RTX.
- `Test-NeuralDoom-Smoke.ps1 -Profile DLAA -DLSSPresetMatrix -Configuration Release
  -Frames 60 -WarmupFrames 180 -ExpectedProbeLighting Local -ValidationLayers 1
  -RayTracedAO -RayTracedContactShadows -RayTracedGI -RayTracedReflections` passed.
  At 1280x720 output, SDK-selected inputs were Quality 853x480, Balanced 742x418
  and Performance 640x360. Returning to DLAA restored 1280x720. All 597 evaluated
  frames presented, zero rejected; lighting toggles/history and local probes
  passed. Artifacts remain under ignored `captures/neural/installer-runtime`.
- The Native SDK-OFF Release smoke passed with all optional lighting effects off,
  valid local probe lighting, primary-view progress, history resets and no device
  failure. This confirms the independent Native installation remains functional.
- The first preset run caught a one-frame DLSS-to-DLAA extent mismatch. Pairing
  mode/quality with each frontend view fixed it; the repeat above had no rejected
  frames. An incomplete hand-assembled test folder initially omitted tracked
  `base/def` files; adding the same definitions already included by the packager
  restored probe population. This was a fixture defect, not missing package data.
- `Test-InstallLifecycle.ps1` passed failure rollback, successful replacement,
  obsolete-file cleanup, separate-copy save preservation, ownership-based
  uninstall, modified/unrelated-file preservation and traversal rejection.
- `Test-NeuralInstallerComponents.ps1` passed against the real hash-pinned five
  archives, including official ReShade SFX extraction and local NVIDIA-signed DLL
  selection. It confirms no Native download, no DXGI proxy, NR full-resolution
  settings, Streamline hooks, F6 key 117 and preserved appearance tuning.
- Wizard compilation, all-page render inspection and redirected worker
  success/failure tests passed. Download retry/cache/publisher/cancellation and
  public-source privacy fixtures passed. Full installer artifact checks follow
  the committed source identity recorded in its manifest.

Visual acceptance remains manual: compare presets and F6 in motion, use the
ultrawide display, resize, visit menus and relaunch with saved preferences. This
does not certify NR model output or public redistribution rights. Next task:
the short installer/profile playtest in INTERNAL_TESTING.md.

NR startup validation selected consumer 4.70 with RHI NR 310.8.SF-v2, matching
all runtime DLL hashes from the working local setup. With hooks enabled, all
117 DLAA frames presented without rejection; the consumer separately confirmed
successful feature-18 NR evaluations at native 1280x720. Hooks disabled only
bypassed NR and was not counted as a pass. Signed NR 310.8.0, the older SF
revision and consumer 4.5 combinations failed or rejected evaluation; setup now
pins the successful combination and rejects different locally selected NR DLLs.
This does not expand binary redistribution approval.

A bounded Native Release test deliberately made the logfile target a directory.
The game still executed its config, wrote the completion config and exited 0.
The optional-log failure no longer terminates startup.

Final package validation used the committed b77ca4ce payload and identical
engine hashes to the renderer smoke tests above. The single-file EXE verified
its embedded payload. An actual fresh NR installation completed from an empty
folder with a verified download cache and owned BFG data; all three installed
launcher profiles passed ValidateOnly. Package verification rejected a changed
shader and a path escape, restoring its fixture exactly afterward.

An actual upgrade from the previous 2551d347 Native package also completed,
preserving a saved-game fixture, saved reconstruction/lighting preferences and
NR appearance settings. The new setup selection correctly took precedence over
an older saved Native launch preference for the next launch. The UI worker
success/failure paths passed against the packaged EXE. Only fixtures were changed;
the tester's existing installation was not modified.

A combined NR plus all four RTX effects run presented all 173 evaluated frames
at native 1280x720 with zero rejections. The add-on separately reported successful
feature-18 neural evaluations. The first harness assertion assumed an exact
number of rendered frames from console wait ticks; recorded counters establish
the pass, since rendering and console ticks differ. A subsequent startup check
confirmed the separate F6/virtual-key-124 bindings. These final helper/documentation
changes are repackaged from their clean commit; engine binaries are unchanged.

## 2026-09-07 - Installer dropdown disposal fix

`InternalSetup.cs::ChoiceButton` disposed its ContextMenuStrip in the Closed
callback, before WinForms finished its item-click cleanup. The menu now belongs
to the button, is reused for selections, and is disposed with that button.
`Test-InternalSetupWizard.ps1` reproduces the released 82adc605 exception through
real ToolStripItem.PerformClick dispatch, then passes with the fix. It covers
repeated action, existing-install and renderer selections, dismissal, page
recreation, and the existing worker success/failure paths. No game, renderer,
runtime pins, installation data or settings changed. The C# UI build passed;
the complete installer is regenerated with matching committed source and the
unchanged Native and neural Release engines. Next check: choose Upgrade / repair
using the replacement installer.

## 2026-09-07 - Release review, launch controls and FPS

Focused review found and corrected:

- `ambient_occlusion.cs.hlsl` and `contact_shadows.cs.hlsl`: dynamic ray hits
  used a BLAS-local primitive index against the shared triangle buffer. Include
  `CommittedInstanceID()` as the global triangle offset, matching GI/reflections.
  The old normal lookup could bias contact rays into moving doors. Triangle
  layouts, world-space coordinates and resource formats are unchanged.
- `RenderWorld.cpp::RenderScene`, `GLMatrix.cpp::R_SetupProjectionMatrix`,
  `RenderCommon.h::viewDef_t`, and `RenderBackend.cpp/.h`: snapshot temporal-AA
  eligibility per view before choosing the DLSS input viewport and jitter.
  Disabling AA now restores the full viewport. Keep camera/object motion validity
  separate from native TAA feedback; successful DLSS does not populate that
  feedback. Auxiliary captures do not overwrite primary previous-camera matrices.
  Motion-vector units, formats, sign and jitter conventions are unchanged.
- `RenderSystem_init.cpp`, `RenderBackend.cpp::PostProcess`,
  `postprocess.ps.hlsl`, and System Options: `r_filmicPostFXIntensity` is an
  archived 0–1 blend, default 1; its menu uses 5% steps. The existing float4
  constant `rpJitterTexScale.z` carries intensity, with no resource/layout change.
  Zero bypasses the SDR effect; 100% retains its previous output. Native HDR
  retains its existing bypass.
- `Common.cpp::com_showFPS` defaults to 1. System Options (`MenuScreen.h` and
  `MenuScreen_Shell_SystemOptions.cpp`) adds FPS Counter with archived on/off
  persistence. Existing `Console.cpp::DrawFPS/Resize` already anchors it to the
  current top-right safe area, independently of HUD width. Saved values survive.
- `sys_session_local.cpp/.h`: `com_startInDoom3` defaults on. A one-time startup
  sign-in uses existing profile/save enumeration and the normal transition to
  the Doom 3 menu. `+set com_startInDoom3 0` retains the game selector; later
  session/sign-out transitions are not automatically bypassed.
- `LaunchPicker.cs/.ps1` and `Start-NeuralDoom-Dogfood.ps1`: show available
  profiles before interactive startup, retain setup/menu preferences, and persist
  explicit DLSS quality choices. NR stays native DLAA and SDR; it never inherits
  a saved reduced-resolution DLSS preset. Explicit profiles and validation paths
  bypass the picker. `InternalSetup.cs` preserves Back-navigation drafts and
  permits cache-only retries. Normal helper logs omit redundant diagnostics.

Validation completed from isolated fixtures:

- DX12 configured with ray tracing ON; SDK-on RelWithDebInfo and both SDK-on/off
  Release builds passed using `Configure-RBDOOM-DX12.ps1` and
  `Build-RBDOOM.ps1`. No new dependency or runtime version was introduced.
- `Test-NeuralDoom-Smoke.ps1 -TemporalTransitions -RayTracingDiagnostics Synthetic`
  passed six DLAA/DLSS/AA-off/native-TAA transitions and synthetic static/dynamic
  ray diagnostics. Native viewports returned to 1280x720; motion history resumed
  with nonzero object-motion draws and zero SDK rejections.
- Separate `-DLSSPresetMatrix` and all-four-RTX runs passed. At 1280x720 output,
  Quality/Balanced/Performance used 853x480, 742x418 and 640x360 inputs. RTX
  counters, history resets and each effect's off/on rollback passed.
- SDK-off `-FilmicBlendMatrix` passed pixel checks: zero/bypass mean error
  0.0001, 50%-blend midpoint error 0.2767, full-effect difference 8.9871, in
  8-bit channel units. The scene and jitter were held fixed for comparison.
- Fresh startup runs with `com_startInDoom3` 0 and 1 exited successfully and
  respectively retained the selector or signed in to IDLE before quitting.
  Both reported FPS default 1 and saved an explicit change to 0.
- Launcher UI tests passed component availability, saved/default choices, all
  reconstruction mappings, NR isolation, explanation text fit and Play/Cancel.
  Embedded-NR preparation fixtures passed profile priority, saved DLSS presets,
  explicit quality persistence and preservation of player tuning.
- Installer lifecycle/dependency/wizard tests passed, including repeated menu
  selection, Back navigation, retry cache, upgrade rollback and saved settings.
  CPU tests covered scrolled menu selection, SWF hover lifetime, dynamic geometry
  and safe F-key bindings. Compiled reflection contracts passed 64 permutation
  lookups and resource layouts. Public-source/index/binary privacy checks passed.

No installed player folder was modified. Visual acceptance remains manual,
especially the reported F8 door angle, moving reflections, NR appearance and HDR.
Next task: the five-minute check in `INTERNAL_TESTING.md`, using the rebuilt
installer and its matching source revision.

## 2026-09-07 - Milestone 1 source review; execution deferred

NR-specific reconstruction choices and viewport routing are implemented for branch
testing. Reviewed the changed source, preference isolation, menu/key control flow,
input/output dimensions, existing temporal resets and fallback paths. Corrected
the regression harness's fully qualified menu symbol during review.

No configure/build command, test executable, game, runtime fixture, installer or
benchmark was run for this checkpoint. RelWithDebInfo/Release compilation,
control regressions and GPU validation are **PENDING**, as requested. Earlier
release results above do not validate this feature. No performance gain or working
NR + DLSS combination is claimed; reduced-input handling with the existing
`NREnableUpscaling=0` consumer configuration is an unresolved runtime gate.

Next checks (in a separate branch build/test installation):

1. Build SDK-off/on RelWithDebInfo and SDK-on Release. Run
   `Test-NeuralReconstruction.py`, `Test-LaunchPicker.ps1`,
   `Test-NeuralEmbeddedNR.ps1`, and existing safe-key/menu regressions.
2. Confirm unchanged NR + DLAA and SDK-only/native fallbacks, then test Quality
   with actual input/output extents and successful consumer NR evaluations.
3. Test Balanced/Performance individually, F1/F6, resize/FOV, moving scenes,
   save/load and relaunch persistence. Obtain manual visual acceptance.
4. Measure Release frame times against the DLAA baseline using the performance
   plan. Keep the branch unmerged and the published installer unchanged meanwhile.

## 2026-09-08 - Milestone 1 local build and DLSS viewport correction

Built branch `codex/milestone-1` from `4587dcfb` for a separate local playtest.
Initial SDK counters accepted all presets, but visual inspection exposed a real
viewport mismatch: the legacy crop anchored reduced input to the bottom of the
texture while Streamline tagged input starting at `(0, 0)`. At 1280x720 output,
Quality consumed 240 blank rows out of 480; Balanced consumed 302 out of 418.
Successful SDK evaluation alone did not establish a correct image.

- `neo/renderer/RenderWorld.cpp::idRenderWorldLocal::RenderScene` now selects the
  existing explicit zero-origin crop overload for backend 3. Native TAA, DLAA,
  irradiance captures and legacy resolution scaling retain their existing paths.
  Formats, motion sign/units, jitter and output dimensions are unchanged; the
  rendered color/depth/motion/mask region now agrees with the tagged input extent.
- `tools/neural-rendering/Test-NeuralReconstruction.py` executes the actual crop
  and viewport-routing bodies. All 24 DLSS input-coverage cases and 24 legacy
  cases pass, including NR profiles, resize and unavailable SDK. Injecting the
  original crop in memory makes the regression fail.
- Configure: `Configure-RBDOOM-DX12.ps1 -BuildDirectory <sdk-or-native-tree>
  -RayTracing ON`, retaining the existing pinned SDK ON/OFF cache settings.
  Build: `Build-RBDOOM.ps1 -BuildDirectory <tree> -Configuration
  <RelWithDebInfo-or-Release> -Parallel 16`. All four builds passed, including
  rebuilds after the crop correction. No new dependency or runtime pin was added.
- Focused review and launcher/preparation, reconstruction, safe-key, menu
  selection and SWF lifetime regressions passed. Launch-picker tests used the
  packaged Windows PowerShell 5.1 shell; PowerShell 7's WinForms compilation
  environment lacks an assembly reference for that test.
- GPU temporal transitions and synthetic static/dynamic ray checks passed.
  After the correction, the Release SDK preset matrix with all four RTX effects
  and the SDK-off RelWithDebInfo native smoke passed. One earlier native smoke
  under compilation load missed its primary-view count threshold; deterministic
  fixed-tic smoke reruns passed. These runs are correctness checks, not benchmarks.
- Corrected Release NR runs on RTX 5090 / driver 616.64 completed at 1280x720
  output: DLAA 341, Quality 477, Balanced 199 and Performance 476 presented engine
  frames, each with zero rejections and exit 0. Input extents were respectively
  1280x720, 853x480, 742x418 and 640x360. Each separate process logged successful
  inline NR evaluations at counts 1 and 60. NR processed 1280x720 reconstructed
  color with guides at the selected input extent; `NREnableUpscaling=0` remained
  unchanged. NR processing itself did not become lower-resolution.
- Inspected pre/post-fix scene captures: reduced-resolution SDK output now fills
  the image. NR captures are retained for the local playtest. Full motion, F1/F6,
  ultrawide, resize, save/load and artistic acceptance remain human checks.

Evidence is local and ignored: `captures/neural/milestone1-*.log`, plus isolated
`smoke-*` and `nr-milestone-*` folders in the playtest installation. The prerequisite
script incorrectly included `.gitmodules` from ignored research archives; direct
`git submodule status --recursive` verified all four actual engine submodules.
The normal installed game was not modified; data, runtimes and saves were copied
to a separate local folder. No proprietary assets/runtimes entered source control.

Next: playtest the corrected branch build, especially live F1/F6 changes and
moving scenes at the user's output resolution; then measure median/p95 frame
times under OPT-001. No measured speedup or general visual acceptance is claimed.

## 2026-09-08 - Glass composition and reduced-input screen-material regressions

The first playtest reported newly unstable emissive/reflected lighting and
opaque-looking glass/exhaust effects. The player clarified that intermittent
black surfaces with F11 also occurred in the previous stable build: that older
issue is tracked separately and is not claimed resolved here. Inspection found
two independent defects; these were not attributed to the texture pack.

- `RenderBackend.cpp::DrawViewInternal` previously replaced captured opaque probe
  specular after generic transparency and fog had attenuated that probe in HDR.
  Subtracting the original, unattenuated probe could clamp to black; adding bounce
  at that point also bypassed foreground transmission. Normal
  `R_RenderRayTracedGI` now executes immediately after `DrawInteractions`, before
  SSR snapshots, generic materials, fog and refraction. Its `debugPass` argument
  in `RenderCommon.h` and `RayTracingDiagnostic.cpp` preserves late F10 diagnostic
  output while selecting exactly one lighting dispatch. Graphics state is
  invalidated after lighting, including the copy-only failure fallback.
- `rt/diffuse_bounce.cs.hlsl` and `rt/reflections.cs.hlsl` add supported material
  emission to the earlier interaction-color cache exactly once. Late diagnostic
  cache accounting remains unchanged; `rt/ray_materials.hlsli` documents the
  cache boundary. `GatherStaticWorld` excludes subview/mirror materials, matching
  existing dynamic-geometry coverage.
- In backend 3, both `_currentRender` blits now crop their source to the actual
  DLSS input viewport and expand it over the existing output-sized snapshot.
  Legacy screen-color consumers therefore retain view-relative normalized UVs.
  `builtin/legacy/bumpyenvironment2.ps.hlsl` instead fetches screen normals at
  absolute raster pixels. Both `builtin/lighting/ambient*_IBL.ps.hlsl` shaders
  normalize AO coordinates by the AO texture dimensions, preserving the clamped
  white-texture fallback. The new SSAO and RT AO producers already wrote absolute
  input-viewport pixels into the output-sized AO allocation.
- No resource format, motion/jitter convention, SDK/runtime pin or dependency
  changes. Main DLSS input remains zero-origin; full-size native/DLAA snapshot
  selection is unchanged. Legacy SSAO (`r_useNewSsaoPass=0`) and its fullscreen
  debug display are separate reduced-resolution follow-ups.

Validation:

- Configured DX12/RT ON with `Configure-RBDOOM-DX12.ps1`, then built SDK ON/OFF
  RelWithDebInfo and Release using `Build-RBDOOM.ps1 -Configuration <config>
  -Parallel 16`: all four passed.
- `Test-RayLightingComposition.py` executes source-derived composition and
  emission expressions: 18 glass/fog energy cases, single-dispatch debug routing
  and cached/offscreen emission cases pass; deliberate broken ordering/emission
  mutations fail. `Test-NeuralReconstruction.py` executes the actual snapshot
  crop and AO/SSR coordinate snippets across presets, resize and viewport offsets;
  the original fullscreen-snapshot negative control fails as expected.
- Independent focused review and `git diff --check` passed.
- At the same copied Mars City quicksave, a 2560x720 DLSS Quality baseline
  (1707x480 input) showed a duplicated smaller scene rectangle even with RTX off.
  The repaired Release build removes it with RTX both off and on. All six
  DLAA/Quality off/on/off captures retain the same frozen view position; backend
  and RT state checks pass with zero rejected DLSS frames and invalid ray outputs.
  Animated shading still varies, so off-return captures are not claimed identical.
- SDK-on RelWithDebInfo smoke passed all four effects, their history resets and
  off/on recovery, plus the seven F10 modes. SDK-off RelWithDebInfo native smoke
  passed with effects disabled. The first diagnostic run hit a stale test
  expectation for the old raw F4 binding; `Test-NeuralDoom-Smoke.ps1` now expects
  the shipped `rayTracingBounceToggle` command. All seven diagnostic captures
  were present in that run, and the corrected full check passed on rerun.
- Separate Release NR runs passed DLAA, Quality, Balanced and Performance at
  1280x720 output, with respectively 466/477/477/477 presented engine frames and
  zero rejections. Every process logged successful consumer evaluations at
  counts 1 and 60. Inputs were 1280x720, 853x480, 742x418 and 640x360; NR retained
  output-sized reconstructed color and input-sized guides. These are correctness
  checks on RTX 5090 / driver 616.64, not performance measurements.
- Evidence remains in ignored `captures/neural/material-*` folders. Player saves
  and settings were copied for testing, and their source hashes remained intact.

Known limit: additive translucent per-light interactions still enter the early
radiance cache; generic alpha, fog and screen-warp stages now follow composition.
This remains a hybrid one-bounce renderer with limited material coverage. Next:
re-test the reported glass, mirrors and ship exhaust in live motion at the player's
resolution before accepting this branch for a PR. The reproduced screen-coordinate
artifact is resolved; general visual acceptance remains pending.
Reproduce the older intermittent F11 black-surface case separately; the composition
correction may help it, but the saved-camera toggle check did not establish that.

## 2026-09-08 - Reduced-input material pulsing and temporal-coordinate corrections

The next playtest reported floor/material bulging and pulsing that increased from
Quality toward Performance. Source inspection identified three concrete input
errors; visual acceptance is separate from successful SDK evaluation.

- `NeuralTemporalStreamline.cpp::idStreamlineNeuralTemporalBackend::Evaluate`
  converts the engine jitter's Y sign when setting `sl::Constants::jitterOffset`.
  The actual `GLMatrix.cpp::R_SetupProjectionMatrix` moves DX12 raster samples by
  `(jitter.x, -jitter.y)`, while the adapter had reported `(jitter.x, jitter.y)`.
  The adapter now reports the measured displacement in input pixels, +X right,
  +Y down. Projection, jitter sequence, native TAA and shared frame metadata are
  unchanged. NVIDIA's [sample projection](https://github.com/NVIDIA-RTX/Streamline_Sample/blob/main/donut/src/engine/View.cpp)
  and [Streamline constants](https://github.com/NVIDIA-RTX/Streamline_Sample/blob/main/src/StreamlineSample.cpp)
  confirm that its reported jitter agrees with raster displacement.
- `builtin/post/motionBlur.ps.hlsl`, `VECTORS_ONLY` permutation, now fetches
  camera-motion depth and alpha from the absolute raster pixel instead of
  stretching input-view UVs over output-sized textures. Clip/reprojection UVs
  remain input-relative; previous-minus-current motion is multiplied by input
  dimensions so viewport origins cancel. Ordinary motion blur retains its
  previous sampling. The wrong depth was especially harmful to camera-translation
  parallax on nearby surfaces at reduced resolution.
- `RenderBackend.cpp::PrepareStageTexturing`, `TG_REFLECT_CUBE`, builds the SSR
  DDA projection from the raster viewport dimensions rather than display size.
  `builtin/legacy/bumpyenvironment2.ps.hlsl::ReconstructPositionCS` reconstructs
  integer depth fetches at pixel centers. At half input size, the previous
  projection could start a ray twice as far across the depth texture; the
  half-pixel reconstruction error was also amplified in output pixels.
- Resource formats and sizes remain HDR/output RGBA16F, motion RG16F, masks R8,
  and existing device-depth storage. No runtime, SDK, dependency, texture pack,
  jitter pattern, sharpening or mip-bias changes.

Validation:

- `Test-NeuralJitter.py` executes the actual projection method, eight-point
  jitter table and adapter statement: 192 raster/metadata checks pass across
  native/all presets, resize and depth; the original Y sign fails.
- `Test-NeuralReconstruction.py` additionally executes camera-motion fetch and
  displacement expressions with nonzero viewport origins; the old normalized
  depth lookup fails its negative control. `Test-SSRCoordinates.py` executes
  the actual projection block and shader reconstruction: 240 pixel-center round
  trips pass; old display-size projection and corner reconstruction each fail.
- DX12 configured with RT ON using `Configure-RBDOOM-DX12.ps1`; SDK ON/OFF
  RelWithDebInfo and Release builds passed with `Build-RBDOOM.ps1 -Configuration
  <config> -Parallel 16`. SDK builds also passed after the final jitter change.
- Independent focused review and `git diff --check` passed. SDK-on
  RelWithDebInfo smoke passed the DLAA/Quality/Balanced/Performance matrix with
  all four ray effects and rollback; SDK-off RelWithDebInfo native/effects-off
  smoke passed. No performance claim is made from those runs.
- Captured eight settled floor frames at five-frame intervals, 2560x720 output
  and Performance 1280x360 input, before/after with NR off and on. The same copied
  Mars City quicksave, camera position and 65-degree pitch were used. All four
  valid sequences had zero reconstruction rejections; NR consumer evaluations
  succeeded. An initial zero-evaluation/black capture was rejected, and initial
  cinematic captures were excluded from floor comparisons.
- In the central floor ROI, a local linear registration estimate (3x4 patches,
  Gaussian radius 2, brightness-offset term) measured RMS inter-frame drift
  falling from 2.17 to 0.067 output pixels with NR off, and 2.14 to 0.083 with NR
  on. Estimated p95 drift fell from about 4.2 pixels to 0.12/0.15. These are
  image-based estimates over eight frames, not geometric ground truth or a claim
  about every material. The baseline showed coherent vertical oscillation;
  corrected frame sequences retained stable floor structure. Filmic intensity
  0.3 and stochastic ray lighting were retained, so residual pixel variation
  is expected and zero-noise output is not claimed.
- Evidence and the local capture/analysis scripts are isolated under ignored
  `captures/neural/temporal-floor-*` and `pulse-fix-*`. Installed executable,
  configuration, runtime and save-source hashes remained intact during testing.

Next: verify the repaired build during camera movement at the player's display
resolution, especially the originally reported materials. NR-specific material
interpretation may still vary at lower input resolutions. The older F11
black-surface report remains a separate open issue.

## 2026-09-08 accumulated-change review at b00e6922

Read-only code audit of 65 downstream commits against `ea29c006`, with parallel temporal, ray-material and tooling reviews. [Detailed findings and evidence](REVIEW_2026-09-08.md) records seven confirmed downstream defects, three retained compatibility problems, their triggers, and narrow next corrections. No renderer changes, new build, game launch or GPU validation were performed during this review; the user's running playtest was left intact. Ten offline Python/source-derived checks and five isolated PowerShell tooling checks passed, while additional probes exposed gaps in their coverage. Initial source status and accumulated `git diff --check` were clean; only this documentation and the review report were added.

## 2026-09-08 - Launcher presentation and independent settings resets

Follow-up requested after the accumulated-change review. The picker now uses
keyboard-accessible profile and reconstruction cards, explains rendering cost,
and restores its window once on showing. `LaunchPicker.cs::OnShown` addresses
inherited minimized startup; the local trial shortcut also needs normal window
style instead of its previous minimized style. Hidden constructor/event checks
cover 130 combinations. A brief own-window probe from a minimized PowerShell
host observed Visible=true, Normal, IsIconic=false; Windows did not grant it
foreground focus in that automated probe. The rendered form was visually checked.

- Launcher **Restore defaults** resets game/video/audio/controls and ReShade/NR.
  `LaunchPicker.ps1` calls `Reset-NeuralSettings.ps1::Reset-NeuralGameSettings`
  only after confirmation. Explicit settings files are backed up with checksums
  under `.neuraldoom-cache/settings-reset/`; failed edits roll back. Saved games
  and opaque profile files are preserved. Campaign unlocks from configuration
  are retained. ReShade uses the installer's INPUT/NR defaults; custom external
  presets are detached without modifying their files. A running-game mutex and
  linked-path checks guard the transaction.
- In-game **System Options > Restore Game / Video Defaults** independently resets
  game/video/audio/controls. `MenuScreen_Shell_SystemOptions.cpp` adds the action,
  confirmation and restart handling; `MenuScreen.h` declares its row/state.
  ReShade files are untouched. The existing smaller **Doom Lighting Defaults**
  action remains available. Current look tuning is not captured as new defaults.
- `PlayerProfile.cpp/.h::RestoreSettingsDefaults` resets registered archived
  preferences, excluding progress, installation paths and startup-only values;
  it loads shipped bindings and `neural_rtx_contrast.cfg`, enables the four ray
  effects when compiled, and selects DLAA when the active SDK supports it.
  `Serialize` reads all achievements/statistics/DLC data while suppressing old
  preferences/bindings when `neural_settings_reset.pending` contains `version1`.
  `ApplyPendingSettingsReset` preserves the fresh launcher's display/profile/
  reconstruction choice. `sys_profile.cpp::Pump` applies the pending reset after
  loading; `OnSaveSettingsCompleted` consumes the marker only after a successful
  save. Failed/corrupt profile loads cannot be overwritten by subsequent settings
  autosaves while the reset remains pending.
- `win_main.cpp::Sys_SettingsRelaunchCommandLine` removes generated launcher
  preference seeds from **Restart Now**, preserving startup/runtime/filesystem
  arguments and current reconstruction. Its private nonarchived INIT session
  marker retains this behavior across subsequent restarts. Ordinary launches
  keep their existing command line. This corrects downstream review finding 7.
  The menu repeater now uses absolute selection indices and bounds checks,
  correcting the retained scrolled-arrow defect reported in that review.

Validation: independent focused reviews passed. Windows PowerShell 5.1 and
PowerShell 7 reset fixtures passed backups, rollback/retry, mutex exclusion,
linked-path rejection, unchanged save/profile bytes and unlock preservation.
MSVC source-derived `Test-GameSettingsReset.py` passed with ray tracing compiled
off/on, including real save scheduling after a corrupt load and explicit launch
choices. `Test-SystemOptionsSelection.py` passed 544 selections including the
last row; `Test-SettingsRelaunch.py` passed path quoting and repeated restart
cases. Their original arrow/replay behaviors fail the negative controls.

DX12 configured with `Configure-RBDOOM-DX12.ps1 -RayTracing ON` in SDK ON/OFF
trees. All four final builds passed with `Build-RBDOOM.ps1 -Configuration
<RelWithDebInfo|Release> -Parallel 16`, including the repeated-restart marker.
Release packaging uses the existing allowlisted `Build-InternalPackage.py`
workflow and matching clean source/build manifests. No shaders, resource
formats, coordinate conventions, renderer passes or dependencies changed.

One isolated SDK runtime attempt exited before its completion marker; its log
also reported missing game resources/fonts. This is not a passed reset test.
The user was playing another game and requested packaging without further game
launches. Runtime reset/restart and gameplay acceptance are therefore deferred
to user testing. No live user settings were reset.

Next: test both reset actions and Restart Now locally, then choose the preferred
look before revising baseline values. The remaining six downstream review
findings and two retained renderer problems remain separate work.

## 2026-09-11 - Personal settings snapshots and public preview preparation

`Save-NeuralSettingsSnapshot.ps1::Save-NeuralSettingsSnapshot` exports allowlisted
saved game/binding and ReShade/NR settings into a new ZIP with SHA-256 manifest.
It excludes profile progress, saves, runtimes and generated launch commands;
blocks active Doom, pending resets, linked paths and overwriting an existing ZIP;
and reports an absent optional effects preset. `LaunchPicker.cs/.ps1` expose a
save-only event/dialog without closing or changing the chosen rendering modes.
`Reset-NeuralSettings.ps1` shares its existing mutex guard with action-specific
wording. Current settings and shipped baseline values are unchanged.

The Git ignore/source gate now rejects personal settings and snapshot artifacts.
`Test-PublicHistory.py` adds read-only all-ref object inventory/privacy reporting,
complementing redacted Gitleaks. See PUBLIC_READINESS.md for audit scope and limits.
`InternalSetup.cs::SetupWindow` initializes an automatically selected upgrade's
destination correctly, fixing review finding 6 before publishing the preview.

PowerShell 5.1/7 snapshot fixtures, 131 hidden picker states, hidden default-upgrade
navigation, source/privacy tests and focused diff review passed. The picker was
rendered to a bitmap without launching a game. No renderer/shader/resource-format
or dependency change occurred. Release builds/package verification are required
at the final clean source commit. Runtime reset/restart acceptance and selecting
a sanitized, maintainer-approved baseline remain the next player-validation task.
