# Pre-playtest checkpoint - 2026-09-06

The user is handling visual comparisons. No game was launched during the review. All three RelWithDebInfo configurations built successfully and both Native/DLAA local readiness checks passed. See [the review, fixes and three-check playtest](REVIEW_2026-09-06.md).

## Current state

- Full-resolution static-world ray-traced AO, contact shadows and material-aware diffuse bounce; five debug modes and optional bindings. No half-resolution rendering.
- Native scRGB HDR, official optional DLAA, automatic ultrawide HUD layout and FOV 60-100.
- Review fixes: automatic DLAA joint history, correct object-motion depth/jitter handling, RTX cvar history resets, executable/shader bundle identity, and guarded clean builds.
- Supported launchers: `Launch-NeuralDoom.cmd` and `Launch-NeuralDoom-RTX.cmd`. Legacy NR/mod wrappers remain under `tools/neural-rendering/legacy`.
- The game checkout already contains the official 1.6.0 lighting pack; earlier runtime evidence found 98 complete Mars City 2 probe pairs and 93 populated grids. No separate upstream executable installation is needed.

## Validation boundary

Final review binaries compile and pass read-only local setup validation. Their latest renderer changes have not had a new GPU run. The last passing material-lighting gameplay test remains `captures/neural/smoke-20260906-192933-7ef79bd1/result.json` in the game checkout: Native RT, 1280x720 to 1920x1080, debug validation, on/off/resume/resize, normal exit. It predates albedo mode 4 and the review fixes. That evidence must not be attributed to the final binaries.

Remaining gameplay checks: 5120x1440 DLAA/HDR with all RTX features; animated characters/weapon motion and live cvar transitions; map/save reload; new material-shader fallback. The earlier elevator bounce was subtle. Counters do not establish visual impact. See [TEST_RESULTS.md](TEST_RESULTS.md) for exact build evidence.

Fresh-machine setup and combined binary redistribution are unverified. An NR DLL path/URL alone does not assemble the complete legacy bridge. No retail assets or third-party binaries are tracked. GitHub push remains pending the user's login; no automated GPU continuation is scheduled.
