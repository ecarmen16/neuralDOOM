# Codex session 1 — baseline and renderer reconnaissance

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../../README.md) for current guidance.

Work in the current RBDOOM-3-BFG repository. Read `AGENTS.md` and every file under `docs/neural-rendering/` that is referenced from it before acting.

## Hard restriction for this session

Do **not** modify renderer C/C++, shaders, CMake dependency lists, game code, or third-party code. Do not add DLSS, Streamline, NGX, ReShade, RenoDX, or feeder code. Documentation and corrections to the supplied helper scripts are allowed. Do not download proprietary game data or any unofficial/proprietary Neural Rendering runtime.

## Objectives

1. Verify repository state, branch, submodules, and upstream commit.
2. Run `tools/neural-rendering/Check-Prerequisites.ps1` and record the results.
3. Attempt the provided DX12-only configure and `RelWithDebInfo` build. If a prerequisite is missing, do not improvise an unsafe workaround; document the exact blocker and the smallest human action needed.
4. Map the actual Windows DX12 render path from frame/front-end submission through NVRHI command recording, post-processing, UI composition, swapchain/present, and any HDR/tonemapping stages.
5. Locate the exact resources and symbols associated with:
   - final scene color before UI;
   - linear/HDR color before tonemapping, if distinct;
   - depth and its convention/format;
   - TAA or other temporal history;
   - projection jitter;
   - current and previous camera matrices;
   - current and previous object transforms;
   - skinned MD5 joint data;
   - resolution scaling;
   - first-person weapon rendering;
   - GUI/HUD rendering;
   - transparent/particle/emissive passes;
   - D3D12 native device, queue, command list, resources, and swapchain access beneath NVRHI;
   - existing RenderDoc/Nsight/profiling markers.
6. Determine whether true per-pixel motion vectors already exist anywhere. Distinguish camera reprojection, TAA history coordinates, and actual per-object velocity.
7. Identify the smallest plausible insertion point for a HUD-free scene output and the smallest plausible insertion point for a future temporal reconstruction pass. Do not implement either.

## Required evidence

For every conclusion, cite exact repository-relative paths and symbol names. Include resource formats, dimensions, creation sites, ownership/lifetime, and pass ordering when discoverable. Mark uncertainty explicitly and describe how to resolve it.

## Deliverables

Create or update only documentation/helper files:

1. `docs/neural-rendering/archive/RECON_REPORT.md` containing:
   - environment and build result;
   - upstream commit and branch;
   - frame/render-flow diagram;
   - source map with exact symbols;
   - resource inventory;
   - temporal-data inventory;
   - UI/viewmodel ordering;
   - D3D12/NVRHI escape-hatch analysis;
   - top five architectural risks;
   - recommended first code change with acceptance criteria;
   - unresolved questions.
2. `docs/neural-rendering/archive/TASK_BOARD.md` with statuses updated from evidence.
3. `docs/neural-rendering/DECISIONS.md` only when a decision is actually supported.
4. `docs/neural-rendering/archive/IMPLEMENTATION_NOTES.md` with the command transcript and machine-specific blockers.

## Finish conditions

- Run `git diff --check`.
- Show `git status --short`.
- Do not commit proprietary or generated game data.
- Do not claim the baseline runs unless the executable was actually launched with valid local data.
- End with a concise proposed prompt for the next Codex session, scoped to one reviewable code change.

A documentation-only commit is acceptable after reviewing the diff. Suggested message:

```text
chore(neural): document baseline renderer reconnaissance
```
