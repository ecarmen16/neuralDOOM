# Codex task — camera/static motion-vector prototype

Prerequisites: renderer recon and HUD-free scene diagnostic are complete. Do not add a vendor SDK.

Implement an OFF-by-default motion-vector target and debug visualization for static world geometry plus camera motion only.

Before coding, write the proposed convention into `IMPLEMENTATION_NOTES.md`:

- texture format and resolution;
- vector direction;
- pixel/UV/NDC units;
- Y-axis direction;
- current/previous jitter treatment;
- depth convention interaction;
- invalid/disoccluded encoding;
- previous-matrix update point.

Requirements:

- Use actual current and previous view/projection state.
- Do not pretend rigid or skinned objects are solved; identify/visualize their known incorrect behavior.
- Reset history on the already-proven load/cut/resize events available at this stage.
- Feature-off output remains unchanged.
- Debug view includes a zero reference and direction legend or an equivalent inspectable representation.

Validate T01–T03 from `TEST_PLAN.md`. Update docs and propose the rigid-object follow-up separately.
