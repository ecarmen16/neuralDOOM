# neuralDOOM

neuralDOOM modernizes **Doom 3 BFG Edition** on the RBDOOM-3-BFG source port, with optional ray-traced lighting, native HDR, neural reconstruction and ultrawide controls. It remains a hybrid renderer; full path tracing and NVIDIA Reflex are not implemented.

Download the [latest installer](https://github.com/ecarmen16/neuralDOOM/releases/latest). NR and reduced-resolution reconstruction remain experimental; see [known issues](docs/KNOWN_ISSUES.md) for current limitations.

## Install and play

1. Download the setup EXE from [releases](https://github.com/ecarmen16/neuralDOOM/releases).
2. Select your owned Doom 3 BFG installation and a separate destination. Setup downloads prerequisites, verified lighting data and the selected neural components. Existing installations support upgrade/repair, copy and uninstall.
3. Open the installed shortcut. Choose a rendering profile, then **Play Doom 3** opens the Doom 3 menu directly. NR is the initial default when installed; later choices are remembered.

Windows and a compatible DX12 GPU are required; RTX effects require hardware ray tracing. NVIDIA reconstruction requires supported NVIDIA hardware. The installer includes both engine configurations and corresponding source. Retail data and optional third-party runtimes are acquired during setup, not bundled.

See the [player guide](docs/PLAYING.md) for installation, rendering profiles, controls and settings.

## Rendering choices

| Profile | What it does |
|---|---|
| **NR + DLAA / DLSS** | Defaults to native-resolution DLAA; explicit DLSS Quality/Balanced/Performance choices are experimental. F6 toggles NR while preserving reconstruction. Uses embedded compatibility components without a DXGI proxy; native HDR is unavailable. |
| **DLAA / DLSS** | Native-resolution DLAA, or DLSS Quality, Balanced and Performance for reduced rendering cost. Output/HUD stay native; native HDR is available. NR is not loaded. |
| **Native RTX** | Engine TAA and our ray-traced lighting without NVIDIA reconstruction or NR. Native HDR is available. |

All profiles retain the same lighting controls. DLAA uses **100% input resolution**; only explicit DLSS presets lower it. NR remembers its reconstruction separately from the SDK-only profile. Exact dimensions appear in Rendering Status. Visual quality and performance depend on the scene; NR can change brightness and fine detail.

**NR requires SDR output**, with either DLAA or DLSS. The NR profile disables native HDR. For native HDR, choose **DLAA / DLSS** without NR or **Native RTX**.

## What neuralDOOM adds

- Ray-traced material reflections, diffuse/emissive bounce, contact shadows and ambient occlusion, each independently adjustable and bindable. Supported visible opaque doors, props and characters participate in ray tracing.
- F-key controls for individual RTX effects, moving geometry, reconstruction and diagnostic views; see the [controls table](#f-key-controls).
- Native DX12 HDR with separate scene/UI calibration, plus conservative Doom-oriented lighting defaults.
- DLAA and DLSS quality controls in the launcher and System Options.
- Automatic ultrawide HUD layout/scale and a 60–100 Field of View control in Game Options.
- **Flashlight difficulty:** independent Easy, Normal, Hard and Nightmare levels for single-player. Harder levels drain faster, recharge slower and dim the beam, up to 30% dimmer than Normal on Nightmare. Choose **Game Options > Flashlight Difficulty (SP)**.
- **Filmic Intensity**, blending the SDR postprocessing effect from 0% to 100%. Native HDR bypasses it.

## F-key controls

These are the default bindings; existing custom bindings are preserved. Engine comparison keys show a fading message below the FPS counter with the requested setting or selected mode.

| Key | Action |
|---|---|
| **F1** | **NR profile:** cycle DLAA → DLSS Quality → Balanced → Performance → DLAA. **DLAA / DLSS profile:** switch between native-resolution TAA and DLAA, leaving any DLSS upscale preset. No change in Native RTX. |
| **F2** | Toggle moving ray geometry: whether visible opaque doors, props and characters participate in ray tracing. Doomguy's body shadows remain independent of this toggle. |
| **F3** | Toggle ray-traced material reflections. |
| **F4** | Toggle ray-traced diffuse bounce lighting. |
| **F5** | Quicksave. |
| **F6** | Toggle NR in the NR profile, keeping the selected DLAA / DLSS mode. This key belongs to the external NR add-on; the engine cannot report its on/off state. |
| **F7** | Toggle ray-traced ambient occlusion (AO). |
| **F8** | Toggle ray-traced contact shadows. |
| **F9** | Quickload. |
| **F10** | Cycle diagnostic views: scene → AO → contact shadows → material bounce → albedo → reflections → reflection roughness → scene. Enable the corresponding effect to see its diagnostic. |
| **F11** | Toggle all four RTX lighting effects together: reflections, bounce, AO and contact shadows. If any is on, turn all off; otherwise turn all on. Geometry settings and DLAA / DLSS / NR are unchanged. |
| **F12** | Take a Doom screenshot. |
| **F13** | Optional NR comparison screenshot pair, for keyboards or macro pads that provide F13. |

Remap engine comparison actions under **Settings > Controls > Keyboard Bindings > Renderer Comparisons**. If an older configuration is missing these bindings, use **System Options > Install Free RTX Keys** to fill unused keys. See [the full controls guide](docs/PLAYING.md#exact-comparison-controls) for details.

## Build from source

`main` contains the released Milestone 1 implementation. Use the release tag when building the exact installer source. Start with the [Windows build guide](docs/neural-rendering/WINDOWS_SETUP.md). A native RTX build uses PowerShell:

```powershell
git clone --recursive https://github.com/ecarmen16/neuralDOOM.git
cd neuralDOOM
.\tools\neural-rendering\Check-Prerequisites.ps1
.\tools\neural-rendering\Configure-RBDOOM-DX12.ps1 -RayTracing ON
.\tools\neural-rendering\Build-RBDOOM.ps1 -Configuration RelWithDebInfo
```

The optional SDK build is separate and disabled by default. The [documentation index](docs/README.md) links player guides, renderer internals and validation instructions. [Release packaging](INTERNAL_TESTING.md#release-packaging) covers local builds. The [release workflow](docs/neural-rendering/CLOUD_RELEASES.md) builds both engines and the installer on GitHub's standard Windows runners when a version tag is pushed, then attaches verified assets to the existing release or creates a draft if none exists.

## Attribution and licenses

Built on [RBDOOM-3-BFG](https://github.com/RobertBeckebans/RBDOOM-3-BFG) and id Software's GPL source release. [Upstream documentation](README-UPSTREAM.md), [GPL and additional terms](LICENSE.md), [license exceptions](LICENSE_EXCEPTIONS.md), and [dependency provenance](docs/neural-rendering/THIRD_PARTY_AND_LEGAL.md) are preserved. Experimental NR compatibility is not an official NVIDIA engine integration.

See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. Retail assets, credentials, machine-specific paths and runtime binaries do not belong in tracked source. neuralDOOM is not affiliated with or endorsed by id Software, Bethesda, NVIDIA, RBDOOM-3-BFG, ReShade or RenoDX.
