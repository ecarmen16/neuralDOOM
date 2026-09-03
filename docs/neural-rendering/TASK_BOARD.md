# Task board

Statuses: `BLOCKED`, `READY`, `IN PROGRESS`, `VERIFY`, `DONE`, `DEFERRED`.

## Current focus

| ID | Status | Task | Exit evidence |
|---|---|---|---|
| ND3-000 | DONE | Clone, branch, and install starter files | Feature branch and `UPSTREAM_BASE.txt` at `ea29c006` |
| ND3-001 | DONE | Check Windows prerequisites | Prerequisite report passed; local ISPC pinned |
| ND3-002 | DONE | Configure DX12-only baseline | Generated VS2022 x64 build tree; `LAST_CONFIGURE.txt` |
| ND3-003 | DONE | Compile unmodified `RelWithDebInfo` | Successful build; `LAST_BUILD.txt`; staged executable hash recorded |
| ND3-004 | DONE | Launch baseline with local BFG data | User verified DX12/new game and created a save; clean exit |
| ND3-010 | DONE | Renderer reconnaissance | `RECON_REPORT.md` with exact paths/symbols |
| ND3-011 | DONE | Select reproducible test save/scene | User save resumed in Mars City Hangar; stationary and forward-motion captures recorded |
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
| ND3-330 | DEFERRED | Add full DLSS quality-mode/resolution plumbing | Preliminary 67%-to-native Quality mode evaluated 153 frames with zero rejects; not a project priority on RTX 5090 |
| ND3-340 | DONE | Validate RenoDX interception compatibility | Local ReShade log: feature 18 evaluated at 5120x1440; corrected launch produced a user-confirmed visible neural image; no external binaries tracked |
| ND3-400 | DEFERRED | Implement official DLSS 5 backend | Public SDK and legal path required |

Codex should update statuses only from observed evidence and add links to reports/commits where useful.
