# Lighting measurement baseline

Branch: `codex/lighting-diagnostics`, based on the native HDR prototype.

Follow-up: [PROBE_LIGHTING.md](PROBE_LIGHTING.md) records the restored official lighting pack and empty-grid loader fix. The measurements below retain their original missing-pack conditions. Later Native/DLAA ultrawide captures with loaded probes are recorded separately in `TEST_RESULTS.md`.

## Acceptance and scope

Export the existing GPU timers without changing shading, distinguish missing passes
from measured zero, and automate repeated lighting comparisons on an exact verified
build. Require a default SDK-OFF build and smoke run, SDK-ON/DLAA coverage, valid
sample counts and dimensions, and a report with median and p95 times. This work
does not change lighting defaults or select a visual enhancement from one scene.

## Capture mechanism

`neo/renderer/RenderLog.{h,cpp}` adds non-archived `r_gpuProfileFrames` (default 0).
Set it to 1..3600 to capture that many existing graphics-queue timestamp samples.
Setting 0 cancels; changing the requested count restarts capture. After completion
it resets to 0 and writes `base/gpu_profile.csv` under `fs_savepath`. A later capture
overwrites that file, so the automation uses a unique isolated save directory.

The renderer discards the query ring after a request, records query frame IDs and
dimensions with the submitted frame, and holds samples in memory until completion.
It performs no per-sample file I/O or extra GPU queries. Disabled capture does not
allocate sample storage. No image resources, coordinate conventions, dependencies,
shader code, or lighting defaults change.

CSV times are microseconds. An empty cell means no query was issued for that block.
The existing timers record the first occurrence of each block in a frame, so they
do not aggregate every subview. Timers can nest or span command-list submissions;
their sum is not a valid total. `MRB_GPU_TIME` is a graphics-queue timestamp interval,
not CPU time, present latency, or FPS. The NVRHI query-read synchronization is unchanged.

The console's existing SSR statistic is not populated. There is no standalone SSR
timer in this renderer. SSR shading is integrated into other passes, and the screen
resolve before generic shader passes also has no standalone timer. Compare SSR
enabled/disabled as a whole-renderer experiment; do not label an empty/zero counter
as the cost of reflections.

## Automated comparison

```powershell
.\tools\neural-rendering\Test-NeuralDoom-Lighting.ps1 -Width 2560 -Height 720
.\tools\neural-rendering\Test-NeuralDoom-Lighting.ps1 -BuildDirectory build-streamline -Profile DLAA
```

The runner reuses the exact executable, hash validation, isolated configuration,
single-instance guard, bounded timeout, screenshots, and temporal checks from
`Test-NeuralDoom-Smoke.ps1`. It runs these variants, then repeats in reverse order:

| Variant | SSAO | SSR | Shadow samples |
| --- | --- | --- | --- |
| Baseline | On, Donut pass | On | 16 |
| NoSSAO | Off | On | 16 |
| NoSSR | On, Donut pass | Off | 16 |
| Shadow4 | On, Donut pass | On | 4 |

Each fresh run loads `game/mars_city2` at its default spawn without input. Default
warmup is 300 engine wait frames, followed by a screenshot and 30 settling frames,
then 300 GPU samples. World simulation remains active. Output is SDR; resolution
scale is 100%; AA is TAA or DLAA; `r_swapInterval=0`, `com_engineHz=60`,
`com_fixedTic=1`. The existing fixed-tick debug mode bypasses the engine's background
15-Hz sleep and runs one simulation tick per rendered frame. This produces a
throughput workload rather than real-time play. Shadow atlas is on, shadows are
enabled, and light scale is 3. GPU clocks and world animation can still affect
samples. This is a repeatable scene setup, not a deterministic replay or an
end-to-end FPS benchmark. Normal smoke runs do not enable fixed-tick mode.

Each smoke `result.json` holds the build identity, variant, dimensions and pass
median/p95 in milliseconds, including measured/missing counts. `lighting.json`
collects the eight runs. Local logs/configs/PNGs/CSVs stay ignored. Analysis must
record hardware, driver, missing local assets and run-to-run variability before
making any performance claims. Other apps can contend for the same GPU.

The requested client size must fit the windowed desktop. Windows can clamp a
desktop-sized window to leave room for its borders/title bar. The runner rejects
that mismatch instead of silently reporting timings for the requested size.

`Measure-NeuralGpuProfile.ps1` rejects incomplete captures, wrong dimensions,
duplicate/out-of-order query frames, nonfinite/negative values and missing/zero
total GPU samples. `Test-NeuralGpuProfile.ps1` exercises these failure cases and
the distinction between a measured zero and an absent pass.

## Results and next task

Validated on 2026-09-06: DX12 RelWithDebInfo, RTX 5090, NVIDIA 610.47
(UMD 32.0.16.1047), Windows build 26100.9168, SDR 4800x1350 (32:9), bridge off.
Eight Native runs used the reversed variant order; two additional runs checked
DLAA with baseline lighting. Each run used 600 warmup frames and 300 GPU samples.
The ranges below show the two runs separately, not pooled percentiles.

| Configuration | Median GPU interval (ms), range across runs | p95 GPU interval (ms), range across runs |
| --- | --- | --- |
| Native Baseline | 1.504-1.507 | 1.522-1.522 |
| Native NoSSAO | 1.266-1.271 | 1.281-1.285 |
| Native NoSSR | 1.469-1.471 | 1.488-1.489 |
| Native Shadow4 | 1.423-1.431 | 1.440-1.441 |
| DLAA Baseline | 1.964-1.970 | 2.000-2.043 |

The first native baseline measured SSAO at 0.223 ms, ambient lighting at 0.102 ms,
shadow-atlas rendering at 0.080 ms, and direct light interactions at 0.230 ms.
Reducing shadow samples affects filtering in the interactions pass; it does not
reduce the number of shadow-map draws. Comparing the average of the two run
medians, the full-frame changes are approximately 0.238 ms for SSAO off, 0.036 ms
for SSR off and 0.079 ms for four shadow samples.
These are workload-specific marginal observations, not recommended quality cuts.
DLAA's full-frame difference includes its input generation and integration; there
is no standalone DLAA timer, and TAA correctly appears absent when bypassed.

The initial 2560x720 pilot exposed substantial power-state/background-sleep noise.
It is retained as diagnostic evidence and superseded by the fixed-tick comparison.
The rejected 5120x1440 window actually rendered at 5104x1401; no timing claim uses
those mislabeled dimensions. See `TEST_RESULTS.md` for exact artifacts and checks.

The scene logs 392 missing environment-image warning lines. Reflection comparisons
therefore describe the current incomplete local content state, not fully provisioned
probe lighting. Next: audit probe loading/fallbacks and locally available bake inputs,
then add two fixed-camera scenes with different reflective materials and shadow
coverage before choosing a lighting refinement. No lighting defaults changed.
Actual HDR brightness and artistic preference still require eventual display review.
