# Development checkpoint

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../README.md) for current guidance.

## Current package

The graphical internal setup offers Native RTX, DLAA/DLSS and experimental NR,
with automatic verified downloads or local signed DLL selection. It detects
existing installs and supports upgrades with rollback, separate copies and
uninstall while preserving saves/settings. Both engine configurations and their
corresponding source are packaged; third-party runtimes are acquired at install
time. See [INTERNAL_TESTING.md](../../../INTERNAL_TESTING.md) for exact controls.

## Renderer state

- Full-resolution ray-traced material reflections, diffuse bounce, contact
  shadows and ambient occlusion, with independent settings and comparison keys.
- Supported visible opaque rigid and animated geometry in the ray scene.
- Native HDR, DLAA and DLSS Quality/Balanced/Performance, ultrawide HUD/FOV controls.
- Conservative lighting defaults; display calibration remains independent.
- Full path tracing, off-screen dynamic coverage and secondary-hit history
  remain future work.

## Validation boundary

Build, shader-contract, setup and automated runtime evidence is recorded by
checkpoint in [TEST_RESULTS.md](TEST_RESULTS.md). Evidence for an older artifact
must not be attributed to a later binary. The graphical installer has compile,
payload, UI-worker success/failure and cancellation checks; fresh-machine
installation and visual acceptance remain required.

Use [TEST_PLAN.md](../TEST_PLAN.md) for a repeatable manual test.
Keep raw logs, saves, captures and local configuration backups outside tracked
source. Historical implementation plans remain reference material, not a claim
that every proposed feature has shipped.
