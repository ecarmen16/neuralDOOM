# Research references

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../README.md) for current guidance.

Verified for planning on **August 30, 2026**. These projects and docs can change; Codex must re-check current official versions before integrating an SDK or relying on an API.

## Primary engine/base

- RBDOOM-3-BFG: https://github.com/RobertBeckebans/RBDOOM-3-BFG
- Windows build instructions are in the repository README. At research time they specified Visual Studio 2022, current CMake, optional Vulkan SDK, ISPC at `tools/ispc/bin/ispc.exe`, and the VS2022 CMake batch files.
- Relevant reconnaissance areas observed in the tree include `neo/renderer/NVRHI/`, `neo/renderer/Passes/`, `RenderBackend.*`, `RenderPass.*`, `RenderSystem*`, `GuiModel.*`, `tr_frontend_guisurf.cpp`, `Model_md5.cpp`, and `ResolutionScale.*`. These are investigation targets, not predetermined edit sites.

## Experimental community route

- DLSS5-Feeder: https://github.com/jlrouzies-fr/DLSS5-Feeder
- RenoDX: https://github.com/clshortfuse/renodx
- DLSS D3D11/D3D12 bridge research: https://github.com/NIGos/dlss5-dx11-bridge

The feeder project describes a synthetic DLAA/NGX evaluation built from the completed frame, ReShade depth, and estimated optical-flow motion vectors. Its limitations include approximate motion, temporal artifacts, and UI processing. Treat status and requirements as volatile.

## Official NVIDIA route

- NVIDIA Streamline: https://github.com/NVIDIA-RTX/Streamline
- NVIDIA DLSS developer page: https://developer.nvidia.com/rtx/dlss
- NVIDIA DLSS 5 announcement: https://nvidianews.nvidia.com/news/nvidia-dlss-5-delivers-ai-powered-breakthrough-in-visual-fidelity-for-games

At research time NVIDIA had announced DLSS 5 for a later 2026 release and described integration through the Streamline framework. An announcement is not a substitute for a public SDK contract or redistribution license.

## Alternate original-Doom-3 temporal reference

- DUDE: https://github.com/Inkub0/dude

At research time DUDE described a Vulkan renderer with FSR2 Native AA, motion vectors, and jitter. It is a useful comparative implementation reference but is not the initial branch target.

## Codex workflow

- Codex CLI: https://developers.openai.com/codex/cli/
- Codex Windows sandbox: https://developers.openai.com/codex/windows/
- AGENTS.md guidance: https://developers.openai.com/codex/guides/agents-md/
- Codex command reference: https://developers.openai.com/codex/cli/reference/

The starter uses a repository-root `AGENTS.md`, workspace-write sandboxing, `--cd`, approval-on-request for interactive use, and `codex exec` with stdin for optional non-interactive use.
