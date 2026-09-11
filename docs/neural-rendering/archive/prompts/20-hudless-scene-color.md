# Codex task — HUD-free scene-color diagnostic

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../../README.md) for current guidance.

Prerequisite: `RECON_REPORT.md` is complete and identifies exact pass ordering/resources. Read `AGENTS.md` and the latest implementation notes.

Implement the smallest reviewable diagnostic that exposes the chosen HUD-free scene-color texture before UI composition. Do not add DLSS, Streamline, NGX, RenoDX, or feeder code.

Requirements:

- Follow existing RBDOOM pass/cvar/debug patterns.
- Reuse an existing texture when its lifetime is safe; allocate a new texture only with documented reason.
- Add an OFF-by-default debug mode that presents or saves the HUD-free image.
- Preserve ordinary rendering when disabled.
- Handle resize, map load, HDR/SDR state, and renderer restart according to existing lifecycle patterns.
- Add profiling/debug markers consistent with the renderer.
- Document exact color space, format, dimensions, producer, consumer, and lifetime.

Validation:

- Build `RelWithDebInfo`.
- Show normal output and HUD-free debug output from the same frame/location.
- Confirm HUD/menu pixels are absent.
- Check the first-person weapon separately and record whether it is included.
- Run `git diff --check`, inspect status, and run a focused Codex review.

Update `IMPLEMENTATION_NOTES.md`, `TASK_BOARD.md`, and `TEST_RESULTS.md`. Keep the diff limited to this diagnostic.
