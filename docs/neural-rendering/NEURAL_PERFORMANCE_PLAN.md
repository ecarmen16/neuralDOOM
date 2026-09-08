# Neural rendering performance plan

Planning checkpoint: 2026-09-07. Tested release baseline: `internal-d16dab5e`.
Implementation branch: **`codex/milestone-1`**, from reviewed `main` at `d21c4445`.
Source checkpoint: NR + DLSS preset controls are implemented but unbuilt and
untested. Builds, runtime validation and baseline measurements are deferred to
the next testing session; the published release and player installation are unchanged.

All work in this roadmap stays on the milestone branch. Implement, review and
playtest before opening a PR; `ecarmen16` or `eraser851` must manually approve the latest
changes and perform the merge. No agent merge, auto-merge or direct push to `main`.
See [CONTRIBUTING.md](../../CONTRIBUTING.md) for the local push guard and current
GitHub enforcement limitation. The planning documents already on `main` do not
contain the optimization implementation.

## Priority and intended result

Recover rendering headroom before adding full path tracing. The first playable
target is **NR + DLSS Quality**, followed by Balanced and Performance if validated.
Keep NR + native-resolution DLAA as the initial default and comparison baseline;
lower resolution must remain an explicit choice. Keep output resolution and HUD
native, preserve Doom's shadows, and retain the current F6 comparison.

The reported NR slowdown is roughly 30–40%; it has not yet been reproduced in a
controlled benchmark. Confirm whether this describes FPS or frame time. A 30–40%
FPS decrease corresponds to about 43–67% more time per frame. DLSS may reduce
raster/RTX work while NR still processes a full-output-resolution image. Recovering
the entire slowdown is therefore a hypothesis, not a promised gain.

Full path tracing follows this optimization work. Geometry coverage, sampling and
denoising research can inform the design, but adding a production path tracer now
would add another large cost before the current bottleneck is understood.

## Ordered work

| ID | Priority / dependency | Deliverable | Acceptance |
|---|---|---|---|
| OPT-001 | First | Reproducible NR cost baseline and pass/dimension inventory | Warmed repeated runs separate engine work, NR-enabled overhead and presentation waits; exact versions/settings recorded. |
| OPT-010 | After OPT-001 | Guarded NR + DLSS Quality experiment | NR actually evaluates at the intended dimensions; no stale depth/motion, cropped output, double scaling, device errors or extra frame delay. |
| OPT-020 | After OPT-010 | Supported NR reconstruction choices in launcher/menu | Quality, then Balanced/Performance tested individually; selection persists; F6 preserves the chosen reconstruction; default DLAA and all feature-off paths remain valid. |
| OPT-030 | Guided by OPT-001; before increasing RT scope | Optimize measured RTX/NR integration hot spots | Repeatable median/p95 gains with unchanged selected quality and scene appearance; unnecessary work/copies identified with evidence. |
| OPT-040 | After initial NR/DLSS result; independent of its success | Shared frame identity, Reflex and latency reporting | Correct input/simulation/render/present markers, supported Off/On/On + Boost controls, SDK-off fallback and latency validation. |
| OPT-050 | Requires OPT-040 | Frame Generation, then supported Multi Frame Generation | Correct final-color/UI inputs and presentation lifetime; stable menus/resize/HDR/VRR; genuine off-path rollback and separate rendered/displayed FPS. |
| OPT-060 | After OPT-050 base path | NR + frame-generation compatibility | NR processing, UI composition and presentation hooks agree on the same frame; F6 and reconstruction changes do not desynchronize generated frames. |
| OPT-070 | After measured headroom and scene/denoising gates | Optional path-tracing vertical slice | Controlled reference scenes converge; material energy, off-screen geometry, dynamic objects and temporal denoising are correct before gameplay expansion. |

Each item is a small implementation/review checkpoint. If NR + DLSS is blocked by
the pinned consumer, record the observed failure and retain the supported profile;
continue independent optimization and Reflex work. Do not turn an unproven
combination into a normal menu choice or replace the bridge with undocumented calls.

## OPT-001: measurements that answer the slowdown

Use the existing isolated smoke runner and GPU CSV export. Add only missing
measurements: CPU/frame/present timing and separate AS update, ray dispatch,
filter/composite and reconstruction costs where current markers combine them.
Existing GPU CSV timers cover the graphics queue and first occurrence of a named
block; they can overlap and may omit external NR work. Do not sum them or label an
NR-on/off frame-time difference as pure NR inference time. Identify coverage gaps
and use a targeted capture if the external work is outside the measured interval.

At a fixed output size, compare the following with identical lighting, FOV,
exposure, frame cap, VSync, and HDR state (SDR for NR comparisons):

| Case | Current release | Purpose |
|---|---|---|
| SDK DLAA, NR not loaded | Available | Reconstruction baseline without the compatibility stack. |
| NR profile, DLAA, F6 effect off | Available | Measure the loaded bridge/passthrough overhead. |
| NR profile, DLAA, F6 effect on | Available | Measure the reported slowdown with the same input size. |
| SDK DLSS Quality, NR not loaded | Available | Establish the rendering benefit already available without NR. |
| NR + DLSS Quality, effect off/on | Experimental after OPT-010 | Separate lower rendering cost from any change in NR cost. |
| NR + Balanced/Performance | After Quality passes | Measure further tradeoffs; do not assume Quality proves these modes. |

Start with one fixed camera and one short repeatable route containing a screen,
moving door and character. Warm shaders/history for at least 10 seconds; collect
three 30-second runs per relevant case, alternating order to expose drift. Exclude
loading/compilation from steady-state statistics but report those stalls separately.
Use actual elapsed time, not console `wait` ticks, for performance measurement.
Record median/p95 frame time, rendered FPS, available CPU/GPU timing and VRAM.

Use a modest window for correctness first, then 2560x1440 and 5120x1440 when
available. Query exact SDK input dimensions for each preset. Inventory actual
dispatch sizes and allocation sizes: a reduced viewport alone does not prove that
RTX, filtering, NR or resource-copy work became cheaper. Record whether the run is
GPU-, CPU-, or cap-limited and the display refresh rate.

Working optimization target: at least 10% lower median frame time for NR + Quality
versus NR + DLAA in GPU-limited scenes, with no repeatable p95 regression beyond
5%. These are evaluation targets, not forecasts. Report run-to-run spread and
absolute milliseconds even when the target is missed; no default changes based
on a single FPS reading. Visual acceptance also determines whether a preset is useful.

## OPT-010/020: remove the profile restriction carefully

The published baseline locks NR to DLAA in the launcher, menu and viewport
selection. The milestone source removes those locks for explicit DLSS selections,
with a separate archived NR choice defaulting to DLAA. This is an experiment,
not validated NR compatibility. `NREnableUpscaling=0` controls the external add-on; changing it is
not equivalent to selecting engine DLSS Quality.

1. Keep current runtime pins and the installed player folder unchanged. Use an
   isolated fixture. Lower-resolution NR input requires an explicit experimental
   reconstruction choice; the default remains native DLAA.
2. Trace what the consumer observes around the existing DLSS evaluation: input
   versus reconstructed color, depth/motion extents, motion scale, jitter, exposure,
   reset state and NR dispatch dimensions. Confirm actual NR evaluation, not just
   DLL loading or an apparent FPS increase caused by silently bypassing NR.
3. Permit engine-owned Quality input sizing in the experiment. Audit temporal and
   RTX dispatch extents together; prevent duplicate scaling and mismatched buffers.
   Preserve native output/HUD, darkness, native HDR restrictions and disabled paths.
4. Test static/moving scenes, doors/characters, weapon effects, glass, HUD/PDA,
   resize, FOV change, map/save load, F6 and reconstruction transitions. Check SDK
   rejections and fallbacks; no stale-history or partial-viewport presentation.
5. The branch picker and System Options are implemented ahead of runtime testing
   for source review. Keep the combinations labeled experimental and withhold a
   release/PR until testing determines which choices can be supported.
   Save reconstruction independently of NR appearance enablement. F6 toggles only
   NR; it must not switch Quality back to DLAA. Test upgrades and relaunch without
   asking testers to apply configs. Add Balanced/Performance one at a time.

NR without a DLAA/DLSS evaluation is a later investigation, not a prerequisite for
recovering rendering cost. Do not replace known engine motion/depth with an
estimated feeder input merely to remove the DLAA label.

## OPT-030 through OPT-070: protect future headroom

Prioritize only measured costs: repeated dynamic AS rebuilds, duplicated scene
updates, unnecessary waits/readbacks/copies, full-output dispatches outside the
chosen input viewport, and redundant filtering. Reuse existing NVRHI resources and
passes. Distinguish a same-quality optimization from an explicit sample-count or
resolution tradeoff. Do not silently lower ray samples, lighting strengths or resolution.

Reflex is a separate latency feature. Move frame-token ownership out of the DLSS
evaluation-only path into a common frame lifecycle so timing also works when
reconstruction is disabled. Coordinate game/render threads, input sampling and
presentation without changing Doom's simulation cadence. Validate support and
Off/On/On + Boost behavior using the [Streamline Reflex guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.12.0/docs/ProgrammingGuideReflex.md).

Frame Generation requires Streamline Reflex, consistent frame identity, depth and
motion through presentation, plus matching HUD-free color/UI handling. Handle
loading, menus, resizing and disabled-mode overhead explicitly. First prove the
SDK path, then NR processing/hook order; enable multipliers only when reported
supported. Show rendered FPS, displayed FPS and measured latency separately,
marking unavailable data rather than inventing it. Native DLAA remains a target
configuration; FG must not force downscaling. Follow the [Frame Generation guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.12.0/docs/ProgrammingGuideDLSS_G.md).

Full path tracing remains governed by [RAY_TRACING_PLAN.md](RAY_TRACING_PLAN.md):
persistent ray-scene coverage beyond the camera's visible draw list, correct
materials/light sampling, separate diffuse/specular signals, denoising and an
energy-preserving replacement for existing lighting. NR appearance processing,
DLAA and frame generation do not substitute for those requirements. Evaluate
Ray Reconstruction/other denoising options separately against the required signal
contract. Preserve the hybrid renderer as the default and fallback during this work.
FG is not a correctness prerequisite for path tracing; once headroom and scene
gates pass, an unresolved NR/FG combination need not block reference-scene work.

## Source map and release gates

| Work | Existing files / symbols to extend after inspection |
|---|---|
| Launch/reconstruction policy | `Start-NeuralDoom-Dogfood.ps1`, `LaunchPicker.cs/.ps1`, `MenuScreen_Shell_SystemOptions.cpp::AdjustField/GetField`, `EmbeddedNR.ps1`, `NeuralCompatibility.cpp::ApplyCompatibilityProfile` |
| Input dimensions/temporal state | `RenderWorld.cpp::RenderScene`, `StreamlineIntegration.cpp::R_StreamlineDLSSRenderSize`, `NeuralTemporalStreamline.cpp::Evaluate`, `NeuralTemporal.h::neuralTemporalFrame_t` |
| Timing and frame lifetime | `RenderLog.cpp::FetchGPUTimers/WriteGPUProfile`, `RenderLog.h`, `Common_frame.cpp::idCommonLocal::Frame`, `StreamlineIntegration.cpp::R_StreamlineInitialize`, `neo/sys/DeviceManager_DX12.cpp` |
| Ray work | `RayTracingDiagnostic.cpp::RayTracedAO/RayTracedContacts/RayTracedLighting`, dynamic AS update code, and `neo/shaders/rt/` |
| Regression/packaging | `Test-NeuralDoom-Smoke.ps1`, `Measure-NeuralGpuProfile.ps1`, `Test-NeuralEmbeddedNR.ps1`, `Test-LaunchPicker.ps1`, existing setup/package tests |

Current temporal resources are linear `RGBA16_FLOAT` color/output,
`D24_UNORM_S8_UINT` non-reversed depth, `RG16_FLOAT` previous-minus-current pixel
motion (+Y down), and `R8_UNORM` classification masks. DLSS tags currently last
through evaluation; FG needs appropriate copies or extended validity through
presentation. Re-measure required conversions/lifetimes before changing them.

For each renderer checkpoint: configure/build SDK-on and SDK-off RelWithDebInfo,
run the relevant bounded correctness and feature-off checks, review the diff and
record evidence. Measure performance with Release and validation/debug overhead
disabled; run correctness checks separately with validation enabled. Update
dependency/license records before introducing SDK plugins or changing pins. Keep
third-party runtimes, retail data, captures and personal feedback out of Git.

Publish one reviewed installer checkpoint per useful milestone, with matching
committed source and verified hashes. Next: build the branch separately, run the
prepared control regressions, capture OPT-001 and prove the Quality combination
before accepting Balanced/Performance. No path-tracing or frame-generation code
is included in this source checkpoint.
