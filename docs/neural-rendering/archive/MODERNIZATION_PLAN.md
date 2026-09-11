# neuralDoom modernization plan

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../README.md) for current guidance.

Reviewed 2026-09-06. This is the next implementation backlog, not a claim that the proposed features have shipped.

Implementation began later on 2026-09-06. See `UNATTENDED_WORKFLOW.md` and the dated implementation/test notes for delivered code and current evidence; the initial review below remains a historical snapshot.

Later scope extension: native ray tracing and path tracing were added to the scope. [RAY_TRACING_PLAN.md](RAY_TRACING_PLAN.md) records actual GPU/compiler readiness and the staged scene, shadows, reflections, indirect-lighting and full-integrator work. [PROBE_LIGHTING.md](../PROBE_LIGHTING.md) records the missing lighting-pack repair that establishes the reference for this work.

## Branch and baseline

- Working branch: `codex/modernization-foundation`, created from `76ff35b5`.
- Preserve `feature/neural-rendering-spike` as the previous working checkpoint.
- Recorded upstream base: `ea29c006`; the checkpoint contains 21 downstream commits across 82 changed files.
- The code checkout was clean before this review. Implementation belongs in the initialized source checkout.
- Local `master` and `origin/master` both point to the recorded base. Remote refs were not fetched, so this does not establish that upstream has no newer changes.
- Use this branch for the foundation and small independently reviewable commits. Give later display, UI, and lighting experiments their own `codex/` branches once prerequisites land. Do not combine an upstream merge, SDK upgrade, and visual overhaul in one change.

## What is already working

The September 1-3 entries in `TEST_RESULTS.md` document baseline DX12, camera/rigid/skinned/viewmodel motion, classification masks, shared history resets, the neutral backend, native Streamline DLAA, and manually observed embedded NR gameplay. These are historical results, not fresh runtime validation from this review.

Both SDK-OFF and SDK-ON DX12 build caches and September 3 executables exist. The engine-native integration is DLSS/DLAA. Experimental NR currently runs through the optional embedded ReShade compatibility bridge; successful DLAA evaluation alone does not prove that the external NR layer is active.

The base already provides NVRHI DX12/Vulkan, linear HDR lighting, ACES tonemapping, PBR materials, environment/irradiance lighting, SSAO, TAA, and modern asset tooling. Internal HDR lighting does not establish HDR10/scRGB display output. Build on these existing systems.

## Findings that shape the work

1. **Build automation can produce false confidence.** `Build-RBDOOM.ps1` exits successfully when a successful build yields no discovered executable. `Common.ps1::Find-NeuralDoomExecutable` can fall back from the requested configuration to Release, a root executable, or the newest executable under `build`. The build helper hardcodes `build`, while configuration supports a custom build directory. Fix exact artifact selection before using this tooling as a regression gate.
2. **Validation depends heavily on manual sessions.** There is a tracked source audit, but no dedicated unattended renderer regression runner in `tools/neural-rendering`. Existing counters and reset diagnostics are a useful starting point. Automate rendered-frame evidence, not just process survival or `+quit` startup.
3. **Temporal validation is still shallow.** `NeuralTemporal.cpp` checks resource presence and basic metadata. The Streamline adapter has separate checks. Extend shared validation to actual extents/formats/sample counts, finite camera/jitter values, history discontinuities, and precise rejection reasons. Preserve valid fallback paths.
4. **Visual quality and performance are not comprehensively established.** Historical counters and user checks cover selected scenes. A controlled NR comparison matrix, repeatable frame-time baseline, and wider effects/transition coverage remain necessary.
5. **Setup completion is overstated if treated as universal.** ND3-520 remains VERIFY; clean-install download/redirect and runtime staging paths were not exercised end to end. Existing installation inventory does not prove clean-machine assembly.
6. **D3HDP is more than textures.** The recorded manifest includes definitions, sounds, weapon adjustments, and map extras. Keep native assets as the reference and the pack as an isolated optional profile.

## Ordered implementation backlog

| Order / ID | Deliverable and concrete scope | Unattended acceptance evidence |
|---|---|---|
| 1 / ND3-600 | Build identity: explicit build-directory/configuration selection, fail if exact output is missing, opt-in staging, manifest containing commit/configuration/features/hash. Start in `Build-RBDOOM.ps1` and `Common.ps1`. | Fixture checks for missing/stale/wrong-config outputs; SDK-OFF and available local SDK-ON builds identify their own artifacts; no accidental replacement of the working launcher executable. |
| 2 / ND3-610 | Unattended regression runner with isolated save/config/output paths, bounded execution, owned-process cleanup, structured JSON results, exact executable identity and logs. | Feature-off, null backend, and available DLAA runs reach gameplay, render a minimum frame count, report status, and exit cleanly. Missing optional components are SKIP, not PASS. Timeout/fatal/rejection policies are explicit. |
| 3 / ND3-620 | Shared temporal contract checks and structured rejection/reset telemetry in `NeuralTemporal.h/.cpp`, `NeuralTemporalStreamline.cpp`, and `RenderBackend.cpp`. Add deliberate invalid-input tests using existing project test facilities where practical. | Extent/sample/format and nonfinite metadata failures are distinguishable; first frame, cut, resize, and backend changes reset coherently; fallback produces frames. Zero SDK rejects alone is insufficient. |
| 4 / ND3-630 | Unify launch profile definitions and preflight reporting: native, DLAA, local NR, and independent native/D3HDP content selection. Report requested and active state separately, including restart-required controls. | Generated arguments match profile intent; missing components explain fallback; repeated runs preserve test saves and configurations. Tests use fake component inventories rather than acquiring NR binaries. |
| 5 / ND3-640 | Repeatable performance/capture scenarios and renderer diagnostics: CPU/GPU timing where supported, warm-up, frame-time percentiles, memory/resource counters, capture metadata and comparison reports. | Static/moving camera, door, character, weapon/effects, GUI, and transition runs have reproducible scripts and exact settings. Prove replay suitability before relying on any inherited demo mechanism. |
| 6 / ND3-650 | Temporal quality improvements for existing TAA and NR inputs: audit masks on effects, exposure transitions, disocclusion and viewmodel edges; investigate optional reactive-mask consumption by native TAA. | Feature-off image comparison and motion sequences; no blanket history rejection; quantified coverage/timing. New tuning remains opt-in until visual review. |
| 7 / ND3-660 | Display and readability: audit swapchain color-space/output support; implement explicit SDR/HDR output controls only after capability mapping. Separate scene exposure from UI brightness. Add ultrawide HUD safe-area/scaling and investigate independent weapon FOV. | SDR regression, resize/aspect/layout checks at 16:9/21:9/32:9, deterministic screenshots, capability fallback. HDR display appearance and weapon comfort remain pending human review. |
| 8 / ND3-670 | Lighting/material polish using existing PBR, SSAO and tonemap passes: bounded exposure, bloom controls, material/roughness diagnostics, optional atmosphere-preserving presets. | Shader/build checks, scene comparisons, temporal stability and timing deltas; original look remains selectable. Tune one variable family at a time. |
| 9 / ND3-680 | Content and setup reliability: isolated content manifest, material validation, missing-asset diagnostics, installer fixture tests, source-only CI/build instructions, SDK-OFF portability checks. | No retail/runtime assets in source or CI; idempotent local setup; explicit unsupported/missing dependency results; Vulkan/shared code remains buildable where toolchains permit. |

The first implementation batch is ND3-600 through ND3-620. It makes subsequent code work possible without requesting repeated playtests. UI, display, and material work then have an evidence-producing path instead of accumulating untested defaults.

## Unattended execution contract

- Use owned local retail data read-only and disposable saves/configs for scenarios. Keep generated captures and reports ignored; commit only source, scripts and sanitized summaries.
- Prefer SDK-OFF testing everywhere, plus the already provisioned official SDK-ON configuration where available. Do not download, copy, package, or redistribute user-supplied NR runtimes as part of this work; the existing project constraints still apply.
- Run bounded hidden launch helpers and terminate only processes started by the test. GPU access may be unavailable in a sandbox; report that as unavailable and continue independent build/tooling work.
- Collect actual rendered frames and backend counters. A window, startup log, or successful process exit is not proof of rendering correctness.
- Separate BUILD PASS, AUTOMATED RUNTIME PASS, VISUAL REVIEW PENDING, SKIP, and FAIL. Do not promote subjective quality from a successful compile or a screenshot metric.
- Compare native feature-off output with a fixed reference. For temporal output, use warm-up and sequences; a single-frame pixel diff is not an adequate ghosting test. Measure baseline variability before selecting performance regression thresholds.
- Cover reset/load/resize and unavailable-backend behavior before enabling any feature by default. New visual controls may be implemented and automated while their preferred settings remain pending review.
- Update task board and test notes per meaningful change; run focused diff review and `git diff --check`. Independent build and tooling work can proceed before manual acceptance.

## Modernization priorities and deferred work

### Design priorities recorded 2026-09-06

The ReShade bridge is temporary. Native display HDR, geometry detail, and lighting improvements must work independently of it. NR's apparent dynamic-range enhancement does not replace an HDR-capable presentation path. Ultrawide HUD placement is an immediate usability priority.

Next focused candidates after this foundation:

1. **Native display HDR:** audit `neo/sys/DeviceManager_DX12.cpp`, the swapchain format/capability handling, `TonemapPass`, final composition, and UI brightness. Prototype an explicit linear scRGB or HDR10 path with SDR fallback and output diagnostics. Avoid expanding already-clipped LDR as the HDR source. Microsoft documents the required format/color-space pairing in its [D3D12 HDR sample](https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/Samples/Desktop/D3D12HDR/src/D3D12HDR.cpp). Monitor calibration and perceived brightness still need eventual human review.
2. **Lighting depth:** measure existing SSAO, shadow filtering, SSR and probe lighting before introducing replacements. Prioritize contact-shadow quality and stable reflection/probe transitions. Explore local volumetric beams only after mapping light/shadow inputs and temporal cost. Preserve dark-area readability and the original atmosphere through optional controls.
3. **Surface relief:** investigate opt-in parallax occlusion/relief mapping for authored height-bearing materials. This is surface shading, not extra silhouette geometry. Existing material import code contains reserved displacement comments; those comments are not a working displacement pipeline. Do not derive convincing height automatically from arbitrary diffuse maps without evidence.
4. **Real geometric detail:** keep high-poly replacements, selective mesh subdivision/displacement, or rounded-edge geometry in an isolated content/renderer experiment. Validate silhouettes, collision expectations, animated pose/motion vectors, bounds, seams and shadow consistency. Extra tessellation alone cannot restore detail absent from the authored source.

Each experiment needs original/changed stills, motion sequences, timing, and an OFF path. None of these visual upgrades is represented as implemented by the current foundation batch.

Aim for a sharper, more stable and more readable Doom 3 while retaining its dark lighting and pacing. The highest-value visible work is temporal stability on characters/weapons/effects, predictable exposure, ultrawide HUD composition, and coherent material/lighting controls.

Treat ray tracing/path tracing, ray reconstruction, frame generation, new vendor backends, broad gameplay/AI changes, and a renderer rewrite as separate later projects. They expand the test surface substantially and are not prerequisites for the existing NR path. Full DLSS scaling remains lower priority under the current native-resolution rendering objective. A native NR backend requires a verified public API contract; the compatibility bridge is not that contract.

## Review evidence and limits

- Inspected branch history, downstream diff summary, task board, decisions, architecture/test plan excerpts, recent test results, texture-pack evaluation, backend/compatibility source, launchers, and build/audit scripts.
- `git diff --check` passed before the documentation edit; final check is recorded with this task.
- Public-source audit with `-AllowDirty`: PASS, 2,445 tracked files. The flag means worktree cleanliness is established separately. An initial attempt with a process-local `core.excludesFile=NUL` failed; the successful rerun omitted that override. No persistent Git configuration was changed.
- Attempted PowerShell parser verification was BLOCKED by constrained language mode. The wrapper printed a misleading PASS after parser errors; that line is not accepted as validation.
- No fresh configure/build, gameplay, GPU capture, clean installation, or monitor HDR verification was performed in this planning review. Existing caches/executables are inventory evidence only.
- No engine, shader, runtime, or setup behavior changed during this review.

## Primary references checked

- [RBDOOM source and feature documentation](https://github.com/RobertBeckebans/RBDOOM-3-BFG): existing modernization systems and material workflow.
- [RBDOOM release notes](https://github.com/RobertBeckebans/RBDOOM-3-BFG/blob/master/RELEASE-NOTES.md): renderer evolution and existing temporal/PBR capabilities.
- [Official Streamline DLSS integration guide](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS.md): resource tags and input/output extent integration. Actual implementation changes must use the locally pinned SDK's contract, not assume main matches it.
