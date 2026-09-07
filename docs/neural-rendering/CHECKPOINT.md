# Pre-playtest checkpoint - 2026-09-06

## Current: internal native RTX Release ready for testing

Graphics controls and visible dynamic geometry are implemented. The internal installer/package includes native RTX Release and matching source; DLAA/NR runtimes remain local only. Safe keys use F3 for reflections and preserve F5/F9/F12. See [INTERNAL_TESTING.md](../../INTERNAL_TESTING.md) for exact keys and installation, and TEST_RESULTS.md for current verification. The exported installer, package hash/tamper checks, relocated Release gameplay and resize passed on the development machine. Friends' fresh-machine and visual tests remain pending. Earlier entries below are historical.

## 2026-09-07 - User playtest feedback and brightness tuning

The user reports the lighting/reflections and HDR look good, with screen reflections stronger and overall lighting brighter than desired. The active local NR INI tuning overrides were cleared, retaining only NR enabled and full-resolution rendering. Local playtest bounce was found at 1.5 and set to 1.125; reflection strength was reduced from 1 to 0.65. HDR settings and other controls were preserved. Both original config files were backed up under the ignored `captures/dogfood/tuning-backups` directory.

`base/neural_rtx_contrast.cfg` reproduces the two lighting settings on request. No renderer code or shader changed; existing binaries remain current and no rebuild or game launch was needed. Next: compare the lower reflection/bounce settings, and assess the add-on's restored NR defaults separately. Earlier overnight notes below retain their historical validation boundary.


## Overnight stop — NR controls

The user requested a quick stop for the night. Launcher option 3 / `-Profile NR` now selects the current Streamline build, validates the already-installed embedded compatibility stack, and reserves F6 for its existing NR hotkey. Bounce moves to F4. `-ValidateOnly` is read-only; `-PrepareOnly` stages only the verified engine executable and prepares the local settings without starting the game. No runtime binaries are obtained or copied. Native/DLAA remain independent; NR retains the existing SDR compatibility output.

Offline NR fixtures passed: exact engine staging, proxy/missing component/SDK mismatch/duplicate setting rejection, full-resolution setting, preservation of other NR tuning, F6/F4 separation and no process launch. The NR preparation path has not yet been exercised against the real installation, and no combined NR + RTX gameplay validation was performed. No renderer C++ or shaders changed in this checkpoint, so the preceding tested binaries remain current.

Next session: check real NR readiness/preparation, then launch RTX option 3 manually and verify F6 changes only NR while F4 changes bounce. Confirm full-resolution input and compare against DLAA. The latest reflection pass also still needs the user's visual checks.


The user reported a strong visual improvement with the preceding material-lighting/review build. The next addition is [full-resolution material reflections](RAY_TRACED_REFLECTIONS.md), with the diffuse bounce default reduced 25%. No game was launched for this addition; reflection visual validation remains pending.

## Current state

- Full-resolution static-world ray-traced reflections, AO, contact shadows and material-aware diffuse bounce; seven debug modes and optional bindings. No half-resolution rendering.
- Native scRGB HDR, official optional DLAA, automatic ultrawide HUD layout and FOV 60-100.
- Review fixes: automatic DLAA joint history, correct object-motion depth/jitter handling, RTX cvar history resets, executable/shader bundle identity, and guarded clean builds.
- Supported launchers: `Launch-NeuralDoom.cmd` and `Launch-NeuralDoom-RTX.cmd`. Legacy NR/mod wrappers remain under `tools/neural-rendering/legacy`.
- The game checkout already contains the official 1.6.0 lighting pack; earlier runtime evidence found 98 complete Mars City 2 probe pairs and 93 populated grids. No separate upstream executable installation is needed.

## Validation boundary

The reflection changes build in Native RT, DLAA and RT-OFF configurations. The final artifact identities and CPU checks are recorded in TEST_RESULTS.md. This new pass has not had a GPU run. The last passing material-lighting gameplay test remains `captures/neural/smoke-20260906-192933-7ef79bd1/result.json` in the game checkout: Native RT, 1280x720 to 1920x1080, debug validation, on/off/resume/resize, normal exit. It predates albedo mode 4 and the review fixes. That evidence must not be attributed to the final binaries.

Remaining gameplay checks: 5120x1440 DLAA/HDR with all RTX features; animated characters/weapon motion and live cvar transitions; map/save reload; new material-shader fallback. The user liked the subsequent material-lighting result but requested 25% less bounce; the default and the existing local 1.5 setting were changed to 1.125, with a local config backup. Counters do not establish visual impact. See [TEST_RESULTS.md](TEST_RESULTS.md) for exact build evidence.

Fresh-machine setup and combined binary redistribution are unverified. An NR DLL path/URL alone does not assemble the complete legacy bridge. No retail assets or third-party binaries are tracked. GitHub push remains pending the user's login; no automated GPU continuation is scheduled.
