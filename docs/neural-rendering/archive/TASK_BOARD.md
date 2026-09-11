# Task board

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../README.md) for current guidance.

Statuses: `BLOCKED`, `READY`, `IN PROGRESS`, `VERIFY`, `DONE`, `DEFERRED`.

## Current focus

### Neural performance / 2026-09-07

The next work is [NEURAL_PERFORMANCE_PLAN.md](NEURAL_PERFORMANCE_PLAN.md): measure
the reported NR slowdown, prove NR + DLSS Quality, then optimize measured costs
before Reflex, frame generation and full path tracing. Baseline installer:
`internal-d16dab5e`. Implementation branch: `codex/milestone-1`, created from
reviewed `main` at `d21c4445`. Review and playtest branch builds before opening a PR;
only `ecarmen16` or `eraser851` may manually approve and merge the latest changes.
No optimization implementation is merged into `main` by this branch setup.
Use [PERFORMANCE_FEEDBACK.md](../PERFORMANCE_FEEDBACK.md) for current-release feedback.

2026-09-08: branch SDK/native builds and bounded GPU checks passed after fixing
the DLSS input viewport origin. NR evaluated with all three reduced-input presets
at 1280x720 output. A separate local playtest preserves the existing installation.
Manual visual/motion acceptance and performance measurements remain pending; see
the latest entry in `TEST_RESULTS.md`.

| ID | Status | Task | Next evidence / dependency |
|---|---|---|---|
| OPT-001 | READY | Isolate NR, reconstruction and RTX cost | Repeated Release frame-time measurements, pass/dispatch dimensions and timer coverage |
| OPT-010 | VERIFY | NR + DLSS Quality evaluated with corrected zero-origin inputs | 853x480 guides / 1280x720 NR output passed; motion/ultrawide visual checks and OPT-001 remain |
| OPT-020 | VERIFY | Independent NR presets in launcher/menu/F1, native DLAA default | Control tests and separate DLAA/Quality/Balanced/Performance NR runs pass; live F1/F6 and wider playtest remain |
| OPT-030 | DEFERRED | Optimize measured rendering hot spots | OPT-001 identifies work worth changing; no hidden quality reduction |
| OPT-040 | DEFERRED | Shared frame identity and Reflex | Initial NR/DLSS result; independent fallback work if its compatibility is blocked |
| OPT-050 | DEFERRED | Frame Generation and supported MFG modes | OPT-040 and valid frame/UI/presentation lifetime |
| OPT-060 | DEFERRED | Validate NR with Frame Generation | OPT-050; same-frame NR processing and hook/composition order |
| OPT-070 | DEFERRED | Optional full path-tracing slice | Measured headroom, complete ray-scene coverage and denoising gates |

The 2026-09-07 entries in [TEST_RESULTS.md](TEST_RESULTS.md) supersede older
pending automated-validation statements below. Current visual acceptance remains
open. The older tables retain implementation history and broader unfinished gates.

### Earlier modernization implementation / 2026-09-06

Working branch: `codex/rt-foundation`, prepared from the completed `codex/probe-lighting` checkpoint. See [PROBE_LIGHTING.md](../PROBE_LIGHTING.md) for the lighting-pack investigation and empty-grid fix, and [RAY_TRACING_PLAN.md](RAY_TRACING_PLAN.md) for the next implementation gates. [LIGHTING_BASELINE.md](LIGHTING_BASELINE.md) retains the earlier missing-pack GPU measurements; [NATIVE_HDR.md](../NATIVE_HDR.md) retains the HDR implementation and validation boundary.

| ID | Status | Task | Exit evidence |
|---|---|---|---|
| ND3-600 | DONE | Exact CMake artifact identity and build manifests | Both build variants pass; missing/stale/wrong-config fixture tests pass |
| ND3-610 | DONE | Initial bounded gameplay smoke runner | Native/null/DLAA runs, reset epochs, frame progress, isolated PNGs and structured JSON; wider scenarios remain follow-up |
| ND3-620 | VERIFY | Shared temporal contract validation | Both builds and null/DLAA runtime pass; negative-case injection coverage remains |
| ND3-660A | VERIFY | HUD layout, size and menu controls | Menu changes, archive persistence, relaunch and resolution changes tested; broader notification/combat HUD states remain |
| ND3-660B | VERIFY | Native scRGB presentation, HDR tone mapping and calibration controls | SDK-OFF/ON builds; finite FP16/scRGB and resize checks; active Windows HDR verified with DLAA/RTAO; visual monitor calibration remains |
| ND3-660C | DONE | Opt-in GPU timing export and unattended lighting baseline | Eight Native ultrawide variant runs, two DLAA baseline runs, disabled/lifecycle/CSV validation; missing probes and further scene coverage remain follow-up |
| ND3-660D | DONE | Restore local lighting data and audit probe/grid readiness | SDK-OFF/ON builds and Native/DLAA ultrawide checks pass; 98 complete probe pairs, 93 populated grids, 11 empty areas, zero lighting-image warnings; broader map/art review remains |
| ND3-700 | DONE | Native RT/path-tracing reconnaissance and staged plan | Actual NVRHI capabilities queried on RTX 5090; isolated shader-model-6.5 compile passes; exact scene/material/compiler gaps documented |
| RT-001A | DONE | OFF-by-default GPU intersection tests and static-world audit | 24 known rays including TLAS update; 82,833 map triangles, 131,072 panorama rays, 32 CPU reference matches; Native/DLAA and disabled/missing-shader checks with native DX12 validation |
| ND3-661 | DONE | Synchronize DX12 presentation before releasing resized backbuffers | Reproduced debug-runtime failure with RT compiled out; post-Present fence fixes Native, DLAA/scRGB and default-build resize/shutdown checks |
| RT-001B | READY | Persistent scene registration and material mapping | Next: stable mesh/instance IDs, owned persistent AS resources, map cleanup/rebuild; then rigid/skinned/cutout coverage and selected-light ray shadows |
| RT-AO | DONE | Opt-in static-world ray-traced ambient occlusion prototype | Clean Native/DLAA/compiled-OFF builds; sampled occlusion, live rollback/resume, ultrawide resize, active HDR and two map lifetimes pass; visual acceptance remains |
| RT-REFLECTIONS | VERIFY | Full-resolution native-material reflections, probe replacement, temporal/spatial filter and 25% lower GI default | Native RT, DLAA and RT-OFF builds plus offline shader contracts; GPU playtest pending. See RAY_TRACED_REFLECTIONS.md. |

The implemented diagnostics and exact resource contract are in
[RAY_TRACING_DIAGNOSTICS.md](../RAY_TRACING_DIAGNOSTICS.md). The short manual
pass is [DOGFOOD_CHECKLIST.md](../DOGFOOD_CHECKLIST.md), launched with
`Launch-NeuralDoom-RTX.cmd` in the game checkout. The first gameplay effect is
documented in [RAY_TRACED_AO.md](../RAY_TRACED_AO.md). Full instance/material scene
registration, moving occluders and path tracing remain open.

See `UNATTENDED_WORKFLOW.md` for the implemented controls and test commands, and the 2026-09-06 entry in `TEST_RESULTS.md` for exact evidence and failures.

Planning checkpoint: development branch is `codex/modernization-foundation`, based on `76ff35b5`. See [MODERNIZATION_PLAN.md](MODERNIZATION_PLAN.md) for the initial reviewed state, unattended validation policy, and ordered ND3-600 through ND3-680 backlog. The modernization table above supersedes its initial READY status; older DONE entries below retain their historical evidence.

| ID | Status | Task | Exit evidence |
|---|---|---|---|
| ND3-000 | DONE | Clone, branch, and install starter files | Feature branch and `UPSTREAM_BASE.txt` at `ea29c006` |
| ND3-001 | DONE | Check Windows prerequisites | Prerequisite report passed; local ISPC pinned |
| ND3-002 | DONE | Configure DX12-only baseline | Generated VS2022 x64 build tree; `LAST_CONFIGURE.txt` |
| ND3-003 | DONE | Compile unmodified `RelWithDebInfo` | Successful build; `LAST_BUILD.txt`; staged executable hash recorded |
| ND3-004 | DONE | Launch baseline with local BFG data | User verified DX12/new game and created a save; clean exit |
| ND3-010 | DONE | Renderer reconnaissance | `RECON_REPORT.md` with exact paths/symbols |
| ND3-011 | DONE | Select reproducible test save/scene | Test save resumed in Mars City Hangar; stationary and forward-motion captures recorded |
| ND3-012 | DONE | Capture baseline GPU frame | Full stationary and moving RenderDoc captures; formats/order recorded in `RECON_REPORT.md` |

## Proof-of-concept track

| ID | Status | Task | Exit evidence |
|---|---|---|---|
| ND3-100 | DEFERRED | Install external feeder stack locally | No files committed; versions recorded |
| ND3-101 | DEFERRED | Validate ReShade depth selection | Depth screenshot and scene notes |
| ND3-102 | DEFERRED | Run static/motion/effects A/B matrix | POC report and captures |
| ND3-103 | DEFERRED | Decide aesthetic go/no-go | Written decision with limitations |

## Engine temporal-input track

| ID | Status | Task | Exit evidence |
|---|---|---|---|
| ND3-200 | DONE | Add renderer debug/capture cvar scaffold | `r_neuralDebug` defaults to `0`; enabled/disabled runtime paths and GPU markers verified |
| ND3-210 | DONE | Expose HUD-free scene color | `_neuralHudlessLDR` capture/present path verified around GUI in RenderDoc frame 1567 |
| ND3-220 | DONE | Validate and expose camera/static velocity | `r_neuralDebug 2`; signed static/yaw/strafe checks and RenderDoc frame 1811 |
| ND3-230 | DONE | Add rigid-object velocity | T04 door/lift class and T05 physics-prop settle behavior passed; feature-off regression passed |
| ND3-240 | DONE | Add MD5/skinned velocity | T06-T07 passed; previous CPU joint palette uploaded through a frame-local `t12` binding |
| ND3-250 | DONE | Resolve viewmodel ordering/velocity | T08 passed on `game/mars_city2`; D-007 selects shared scene inputs with dedicated depth-hacked velocity |
| ND3-260 | DONE | Add reactive/transparency masks | T09-T13 combined combat validation; localized red reactive and cyan transparency diagnostics |
| ND3-270 | DONE | Implement history-reset lifecycle | Automated epoch/reason tests and combined visible load/FOV/`vid_restart` regression pass |
| ND3-280 | DONE | Introduce neutral backend interface | Null/debug consumed 1,076 visible gameplay frames with zero rejects; normal TAA/HUD presentation confirmed |

## Official integration track

| ID | Status | Task | Exit evidence |
|---|---|---|---|
| ND3-300 | DONE | Re-verify current Streamline/DLSS docs and license | Official v2.12.0 pinned; local development allowed; GPL binary redistribution explicitly blocked pending legal review |
| ND3-310 | DONE | Add OFF-by-default SDK build option | Default DX12 and isolated Streamline 2.12.0 configurations built successfully; SDK-enabled executable hash recorded |
| ND3-320 | DONE | Integrate native DLAA | SDK evaluated 597 native-resolution frames with zero rejects; saved-game A/B showed no visible regression and only subtle/no readily discernible change from native TAA |
| ND3-330 | DONE | Add DLSS quality-mode/resolution plumbing in the SDK profile | Quality/Balanced/Performance, menu/launcher persistence and viewport/history transitions passed in the 2026-09-07 review; NR combinations are OPT-010/020 |
| ND3-340 | DONE | Validate RenoDX interception compatibility | Local ReShade log: feature 18 evaluated at 5120x1440; corrected launch produced a user-confirmed visible neural image; no external binaries tracked |
| ND3-350 | DONE | Start local NR compatibility stack from NeuralDoom | SDK-OFF/ON builds pass; renamed ReShade runtime was explicitly loaded by the engine, API 18 add-on registered, NR runtime preloaded at D3D12 device init, and user confirmed visible gameplay NR/F6 behavior |
| ND3-400 | DEFERRED | Implement official DLSS 5 backend | Public SDK and legal path required |

## Distribution and setup track

| ID | Status | Task | Exit evidence |
|---|---|---|---|
| ND3-500 | DONE | Rebrand downstream project as neuralDoom | SDK-OFF and SDK-ON targets built as `neuralDoom.exe`; visible version, README, tools, and launch profiles preserve RBDOOM attribution |
| ND3-510 | DONE | Build unified local setup wizard | Real 6.9 GB BFG data and verified D3HDP archive passed; engine/runtime inventory complete |
| ND3-520 | VERIFY | Add guided local acquisition and public-source audit | D3HDP download plus NR file/URL staging implemented; local dry-run and 2,445-file source audit pass; clean-machine end-to-end run remains |

Codex should update statuses only from observed evidence and add links to reports/commits where useful.

## 2026-09-06 review handoff

- DONE: reviewed accumulated renderer/setup changes, fixed DLAA joint history and object-motion jitter/depth, added automatic RTX history resets and shader bundle validation, guarded clean-build targets. All three RelWithDebInfo builds and offline/local readiness checks pass.
- VERIFY: user visual comparisons and live regression checks on the final binaries; no new GPU run during this review. [Findings and three checks](REVIEW_2026-09-06.md).

## 2026-09-11 - Final gate for the next push and PR

- [x] Fading developer toggle overlay and independent flashlight difficulty implemented.
- [x] Hidden player-body ray shadow coverage implemented with per-view/light exclusions.
- [x] RelWithDebInfo build, CPU geometry/battery tests, shader contracts, eight-case GPU diagnostic and isolated map scenario pass.
- [ ] User manually validates the branch build: Player Shadows and Flashlight Difficulty menu, toggle feedback, movement/body shadows, flashlight/muzzle flashes, mirrors/third person, transitions, visual artifacts and frame times.
- [ ] After validation, prepare focused commits, push and PR; obtain latest-commit human review from ecarmen16 or eraser851. Final merge stays with a maintainer.
- [ ] Decide whether to produce the first test release after manual validation; retain existing game-data/runtime distribution constraints.

Build: `build-rt/RelWithDebInfo/neuralDoom.exe`; installed/private builds unchanged.
Use Game Options -> Player Shadows with ray lighting and moving/skinned geometry
enabled. `r_rayTracingPlayerShadows 0` isolates the new ray-body contribution while
keeping native player shadows. See the latest IMPLEMENTATION_NOTES entry for exact
source changes, tests, evidence and known limits.

Manual update (2026-09-11): user accepted Doomguy shadow behavior as working
perfectly. Other gameplay/UI checks remain in progress. Keep the final push/PR
and release gates pending that remaining validation.

Draft handoff update (2026-09-11): user requested the PR now after accepting player
shadows. Open the tested implementation as a draft while other manual checks
continue; the above wait-before-PR gate is superseded. Streamline-enabled build
passed and the default NR/DLAA shortcut launched with both runtimes initialized.
Installed engine/configuration were staged with backups by the existing helper;
no local runtime files are tracked. Final manual validation and human review
remain required before maintainer merge/release.
