# Development checkpoint

## Current package

The internal native RTX Release ships as a graphical setup wizard. It detects
owned BFG data, verifies and extracts supporting downloads, checks Microsoft
prerequisites, and creates a Start menu entry and optional desktop shortcut.
The package includes corresponding source. DLAA and external NR components are
not included. See [INTERNAL_TESTING.md](../../INTERNAL_TESTING.md) for installation
and the exact comparison keys.

## Renderer state

- Full-resolution ray-traced material reflections, diffuse bounce, contact
  shadows and ambient occlusion, with independent settings and comparison keys.
- Supported visible opaque rigid and animated geometry in the ray scene.
- Native HDR, optional DLAA, automatic ultrawide HUD placement and FOV controls.
- Conservative lighting defaults; display calibration remains independent.
- Full path tracing, off-screen dynamic coverage and secondary-hit history
  remain future work.

## Validation boundary

Build, shader-contract, setup and automated runtime evidence is recorded by
checkpoint in [TEST_RESULTS.md](TEST_RESULTS.md). Evidence for an older artifact
must not be attributed to a later binary. The graphical installer has compile,
payload, UI-worker success/failure and cancellation checks; fresh-machine
installation and visual acceptance remain required.

Use [DOGFOOD_CHECKLIST.md](DOGFOOD_CHECKLIST.md) for a repeatable manual test.
Keep raw logs, saves, captures and local configuration backups outside tracked
source. Historical implementation plans remain reference material, not a claim
that every proposed feature has shipped.
