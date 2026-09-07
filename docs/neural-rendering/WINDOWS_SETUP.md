# Windows setup details

## Visual Studio

Install Visual Studio 2022 with:

- Desktop development with C++;
- MSVC x64/x86 build tools;
- a current Windows 10/11 SDK;
- C++ CMake tools are helpful but the project also uses standalone CMake.

The prerequisite checker uses `vswhere.exe` to look for the x64/x86 C++ tools component.

## CMake

Install a current release and enable its option to add `cmake.exe` to PATH. Verify:

```powershell
cmake --version
cmake --help
```

## Git

Verify:

```powershell
git --version
git config --global core.longpaths true
```

Long-path support is recommended for deeply nested C++ dependencies.

## ISPC

Download the current Windows archive from the official ISPC releases page:

```text
https://github.com/ispc/ispc/releases
```

From the repository root, run the existing helper with the downloaded archive or executable:

```powershell
.\tools\neural-rendering\Install-ISPC.ps1 -RepoRoot . -SourcePath '<ISPC archive or executable>'
```

It installs ISPC at:

```text
<repo>\tools\ispc\bin\ispc.exe
```

Verify:

```powershell
.\tools\ispc\bin\ispc.exe --version
```

## Codex on native Windows

Install/update through a current official method. The npm route is commonly:

```powershell
npm install -g @openai/codex
codex login
codex doctor --summary
```

The official Windows documentation recommends the stronger native `elevated` sandbox when available. In `%USERPROFILE%\.codex\config.toml`:

```toml
[windows]
sandbox = "elevated"
```

If enterprise policy prevents it, use the documented fallback rather than disabling sandboxing. This starter never uses `--yolo` or `danger-full-access`.

## Doom 3 BFG game data

Use a legally owned and updated Steam or GOG installation. Common Steam default:

```text
C:\Program Files (x86)\Steam\steamapps\common\DOOM 3 BFG Edition\base
```

Steam libraries may be elsewhere. Run `Setup-NeuralDoom.cmd` and select the owned game installation, or use the PowerShell setup command below.

## Native RTX source installation

Use a recursive clone of `ecarmen16/neuralDoom` and the branch containing the desired checkpoint. In an existing clone, initialize the pinned dependencies with `git submodule update --init --recursive`. Install the prerequisites above first.

Extract `base/_rbdoom_global_illumination_data.pk4` from the official RBDOOM 1.6.0 release; see [PROBE_LIGHTING.md](PROBE_LIGHTING.md). Then run:

```powershell
.\tools\neural-rendering\Setup-NeuralDoom.ps1 -RepoRoot . -GamePath '<owned BFG installation>' -LightingPackPath '<extracted lighting pack>' -BuildEngine -SkipD3HDP -NonInteractive
.\tools\neural-rendering\Setup-NeuralDoom.ps1 -RepoRoot . -ValidateOnly
```

This configures native DX12 ray tracing in `build-rt` and builds RelWithDebInfo. It does not require an NR DLL. Setup checks the exact executable and compiled shader hashes, game data and lighting candidates. Old manifests require a rebuild. Fresh-machine end-to-end installation remains a pending validation item; see [CHECKPOINT.md](CHECKPOINT.md).

## Optional DLAA and legacy neural rendering

DLAA requires a separately configured official Streamline SDK build in `build-streamline`. Supplying `nvngx_dlssnr.dll` does not supply that SDK or its DLAA components.

`Setup-NeuralDoom.ps1` accepts either `-NRRuntimePath '<local DLL>'` or `-NRRuntimeUrl '<HTTPS URL>'` to stage a user-provided NR runtime. That step does not configure or verify the complete ReShade/RenoDX compatibility chain. Those components remain separate local inputs, and the Native/DLAA launcher profiles disable the compatibility bridge. The NR profile uses an already-installed engine-loaded stack, reserves F6 for NR, and stages only the current verified engine executable beside the existing local components. It does not install or copy NR runtimes. The earlier compatibility launchers are in `tools/neural-rendering/legacy`; they expect a separately staged root executable and runtime files. A single DLL path/URL is therefore not a turnkey installation of the legacy neural-rendering setup.

## Optional capture tools

Useful later, not required for the baseline build:

- RenderDoc;
- NVIDIA Nsight Graphics;
- PresentMon or another repeatable frame-time capture tool.

Install capture tools only from their canonical vendor/project sources. Record versions in test results.

`Configure-RBDOOM-DX12.ps1 -Clean` only accepts an existing dedicated build directory inside the repository whose CMake cache matches this source tree. Source, asset and redirected directories are rejected.
