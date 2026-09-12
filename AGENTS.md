# Neural Doom 3 project instructions

Read `docs/neural-rendering/ARCHITECTURE.md`, `docs/neural-rendering/TEST_PLAN.md` and the relevant renderer reference before changing renderer code.

## Mission

Build a reversible, optional, well-instrumented temporal input path around the existing DX12/NVRHI renderer. First prove a clean upstream baseline; then expose reliable scene color, depth, motion vectors, jitter, exposure, reset state, masks, and UI separation. Integrate only official, redistributable SDK components in tracked source.

## Contribution workflow

- Milestone 1 is merged. Use focused `codex/` branches for follow-up changes. Review and playtest renderer branch builds before opening a PR; do not open a planning or tracking PR.
- Keep `main` at its reviewed checkpoint. After branch testing, require manual approval of the latest PR changes by `ecarmen16` or `eraser851`; new changes after approval require renewed review.
- Do not approve, merge, enable auto-merge, or push/cherry-pick milestone changes into `main` as an agent. Only ecarmen16 or eraser851 may perform the final merge. Actions using their credentials through automation are not human approval.
- Keep `core.hooksPath=.githooks`; the pre-push hook rejects direct pushes to `main`. Do not bypass it. This local guard is not server-side branch protection.

## Non-negotiable legal and repository constraints

- Never add or commit Doom 3/BFG assets, `.resources` files, videos, retail maps, or other proprietary game data.
- Never commit or bundle NVIDIA Neural Rendering runtimes. The internal installer may download the pinned public RHI components or import a locally selected validated DLL, as documented in THIRD_PARTY_AND_LEGAL.md. This installation-time workflow does not approve binary redistribution or an official NR engine API.
- Never commit ReShade, RenoDX, DLSS5-Feeder, NVIDIA redistributables, or SDK binary blobs unless a later task has verified both the license and the intended distribution mechanism.
- Do not put credentials, tokens, machine-specific absolute paths, or personal data in tracked files.
- Treat experimental feeder/RenoDX testing as an optional local compatibility layer, not a required engine dependency. The internal installer may automate its documented setup.
- Preserve RBDOOM's GPL and additional-license obligations. Record every new dependency and its license in `THIRD_PARTY_AND_LEGAL.md` before integrating it.

## Phase gates

1. **Baseline:** configure, compile, and run unmodified upstream DX12.
2. **Reconnaissance:** map the real render path and temporal state. No speculative renderer edits.
3. **Diagnostics/output separation:** add only narrowly scoped debug views, capture hooks, and HUD-free scene output.
4. **Temporal inputs:** implement and validate motion vectors, jitter, exposure, history resets, and masks in small increments.
5. **Neutral interface:** introduce an optional engine-facing abstraction; isolate D3D12-native and vendor-specific work below it.
6. **Official DLSS/Streamline:** integrate a current official SDK behind a build option that is OFF by default.
7. **Neural Rendering:** migrate only against a public, documented, legally usable API contract.

Do not skip a gate merely because a later SDK call appears easy to add.

## Build and run

Use PowerShell on Windows. Preferred commands from the repository root:

```powershell
.\tools\neural-rendering\Check-Prerequisites.ps1
.\tools\neural-rendering\Configure-RBDOOM-DX12.ps1
.\tools\neural-rendering\Build-RBDOOM.ps1 -Configuration RelWithDebInfo
.\tools\neural-rendering\Run-RBDOOM.ps1
```

The baseline CMake configuration is DX12-only:

```text
-DFFMPEG=OFF -DBINKDEC=ON -DUSE_DX12=ON -DUSE_VULKAN=OFF
```

Do not delete or restructure upstream renderer backends as part of this work. DX12 is the first target, but shared renderer code must not be unnecessarily hardwired to D3D12.

## Source-change rules

- Inspect actual symbols before naming integration points. Paths listed in the plan are reconnaissance targets, not guaranteed edit locations.
- Match the surrounding idTech/RBDOOM coding style. Avoid drive-by formatting and unrelated modernization.
- Prefer existing NVRHI resources, command lists, render-pass abstractions, cvars, logging, and profiling markers.
- Keep vendor-specific code behind optional CMake definitions such as `USE_STREAMLINE` or a similarly reviewed name. The default build must remain functional without the SDK.
- Do not invent a new frame graph if the existing pass structure can express the change.
- Keep the disabled path pixel-equivalent to baseline as far as practical.
- Add one class of temporal data at a time: camera/static, rigid objects, skinned objects, viewmodel, then unstable/translucent effects.
- Treat motion-vector sign, units, jitter convention, depth convention, matrix layout, exposure, and reset behavior as measured facts. Document them; do not guess.
- UI and the first-person weapon require explicit ordering decisions. Do not silently feed both through a temporal/neural pass.
- Reset temporal history on map loads, teleports, camera cuts, resolution changes, large FOV changes, and other proven discontinuities.

## Documentation

- Write documentation for players and contributors. Describe current behavior, interfaces, limitations and reproducible commands.
- Do not commit conversation summaries, references to the user or maintainer in the third person, personal testing history, session prompts, task diaries, "local only" instructions or future-agent handoffs.
- Put change-specific build/test results and review notes in the PR description. Keep raw logs, captures and temporary experiments in ignored local storage.
- Update existing technical reference only when behavior, resource formats or coordinate conventions change. Do not recreate implementation notes, task boards or a development archive.
- Delete obsolete documentation. Retain historical material only when it contains useful technical reference that is absent from current docs.

## Validation expectations

Before declaring a renderer task complete:

1. Configure and build `RelWithDebInfo`.
2. Run the relevant debug view or capture scenario.
3. Confirm the feature-off path still works.
4. Inspect `git diff --check` and `git status --short`.
5. Run Codex review or an equivalent focused review of the diff.
6. Keep commits small and describe the verified behavior, not merely the implementation.

Useful test cases include a static camera, camera rotation, lateral translation, a moving door/lift, a rigid physics object, an animated MD5 character, weapon bob/recoil, transparent glass, smoke, muzzle flashes, emissive animation, and a camera cut/map transition.
