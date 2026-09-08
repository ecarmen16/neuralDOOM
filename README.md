# neuralDoom

neuralDoom modernizes **Doom 3 BFG Edition** on the RBDOOM-3-BFG source port, with optional ray-traced lighting, native HDR, neural reconstruction and ultrawide controls. It remains a hybrid renderer; full path tracing and NVIDIA Reflex are not implemented.

## Install and play

1. Download the setup EXE from [internal test releases](https://github.com/ecarmen16/neuralDoom/releases).
2. Select your owned Doom 3 BFG installation and a separate destination. Setup downloads prerequisites, verified lighting data and the selected neural components. Existing installations support upgrade/repair, copy and uninstall.
3. Open the installed shortcut. Choose a rendering profile, then **Play Doom 3** opens the Doom 3 menu directly. NR is the initial default when installed; later choices are remembered.

Windows and a compatible DX12 GPU are required; RTX effects require hardware ray tracing. NVIDIA reconstruction requires supported NVIDIA hardware. The installer includes both engine configurations and corresponding source. Retail data and optional third-party runtimes are acquired during setup, not bundled.

See [installation, mode tradeoffs and exact comparison keys](INTERNAL_TESTING.md), or the [five-minute playtest checklist](docs/neural-rendering/DOGFOOD_CHECKLIST.md).

## Rendering choices

| Profile | What it does |
|---|---|
| **NR + DLAA** (default) | Experimental neural appearance processing with native-resolution DLAA input. F6 compares NR against direct DLAA passthrough. Uses embedded compatibility components without a DXGI proxy; native HDR and DLSS upscaling are unavailable in this profile. |
| **DLAA / DLSS** | Native-resolution DLAA, or DLSS Quality, Balanced and Performance for reduced rendering cost. Output/HUD stay native; native HDR is available. NR is not loaded. |
| **Native RTX** | Engine TAA and our ray-traced lighting without NVIDIA reconstruction or NR. Native HDR is available. |

All profiles retain the same lighting controls. NR and DLAA use **100% input resolution**; only explicit DLSS presets lower it. Exact dimensions appear in Rendering Status. Visual quality and performance depend on the scene; NR can change brightness and fine detail.

## What neuralDoom adds

- Ray-traced material reflections, diffuse/emissive bounce, contact shadows and ambient occlusion, each independently adjustable and bindable. Supported visible opaque doors, props and characters participate in ray tracing.
- Native DX12 HDR with separate scene/UI calibration, plus conservative Doom-oriented lighting defaults.
- DLAA and DLSS quality controls in the launcher and System Options.
- Automatic ultrawide HUD layout/scale and a 60–100 Field of View control in Game Options.
- A top-right **FPS Counter**, enabled for fresh settings and toggleable in System Options; saved choices survive resizing and relaunch.
- **Filmic Intensity**, blending the SDR postprocessing effect from 0% to 100%. Native HDR bypasses it.

F3 toggles reflections, F4 bounce, F6 NR, F7 AO, F8 contacts, and F11 all four lighting effects. F5/F9 remain quicksave/quickload. Engine actions can be remapped in Keyboard Bindings; [the full controls table](INTERNAL_TESTING.md#exact-comparison-controls) describes every key and limitation.

## Build from source

Active development is on `codex/rt-foundation`; `main` tracks reviewed internal-test source. Start with the [Windows build guide](docs/neural-rendering/WINDOWS_SETUP.md). A native RTX build uses PowerShell:

```powershell
git clone --recursive https://github.com/ecarmen16/neuralDoom.git
cd neuralDoom
.\tools\neural-rendering\Check-Prerequisites.ps1
.\tools\neural-rendering\Configure-RBDOOM-DX12.ps1 -RayTracing ON
.\tools\neural-rendering\Build-RBDOOM.ps1 -Configuration RelWithDebInfo
```

The optional SDK build is separate and disabled by default. Use the [development plan](docs/neural-rendering/DEV_PLAN.md), [architecture](docs/neural-rendering/ARCHITECTURE.md), and [validation results](docs/neural-rendering/TEST_RESULTS.md) for implementation details. [Maintainer packaging](INTERNAL_TESTING.md#maintainer-packaging) covers the versioned ZIP, single-file EXE and verification steps. Releases are currently built and verified locally, then uploaded; GitHub does not automatically build the installer.

Next focus: [NR + DLSS and rendering performance](docs/neural-rendering/NEURAL_PERFORMANCE_PLAN.md), before full path tracing. Testers can use the [short performance feedback checklist](docs/neural-rendering/PERFORMANCE_FEEDBACK.md).

## Attribution and licenses

Built on [RBDOOM-3-BFG](https://github.com/RobertBeckebans/RBDOOM-3-BFG) and id Software's GPL source release. [Upstream documentation](README-UPSTREAM.md), [GPL and additional terms](LICENSE.md), [license exceptions](LICENSE_EXCEPTIONS.md), and [dependency provenance](docs/neural-rendering/THIRD_PARTY_AND_LEGAL.md) are preserved. Experimental NR compatibility is not an official NVIDIA engine integration.

See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. Retail assets, credentials, machine-specific paths and runtime binaries do not belong in tracked source. neuralDoom is not affiliated with or endorsed by id Software, Bethesda, NVIDIA, RBDOOM-3-BFG, ReShade or RenoDX.
