# Windows setup details

For the released installer and portable ZIP, see the [player guide](../PLAYING.md). This page covers building from source. The installer can download the pinned optional components; the legacy source-setup DLL copying options are unsupported.

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

## Doom 3 BFG game data

Use a legally owned and updated Steam or GOG installation. Common Steam default:

```text
C:\Program Files (x86)\Steam\steamapps\common\DOOM 3 BFG Edition\base
```

Steam libraries may be elsewhere. Run `Setup-NeuralDoom.cmd` and select the owned game installation, or use the PowerShell setup command below.

## Native RTX source installation

Use a recursive clone of the downstream repository and the branch containing the desired checkpoint. In an existing clone, initialize the pinned dependencies with `git submodule update --init --recursive`. Install the prerequisites above first.

Extract `base/_rbdoom_global_illumination_data.pk4` from the official RBDOOM 1.6.0 release; see [PROBE_LIGHTING.md](PROBE_LIGHTING.md). Then run:

```powershell
.\tools\neural-rendering\Setup-NeuralDoom.ps1 -RepoRoot . -GamePath '<owned BFG installation>' -LightingPackPath '<extracted lighting pack>' -BuildEngine -SkipD3HDP -NonInteractive
.\tools\neural-rendering\Setup-NeuralDoom.ps1 -RepoRoot . -ValidateOnly
```

This configures native DX12 ray tracing in `build-rt` and builds RelWithDebInfo. It does not require an NR DLL. Setup checks the exact executable and compiled shader hashes, game data and lighting candidates. Old manifests require a rebuild.

## Optional DLAA and legacy neural rendering

DLAA requires a separately configured official Streamline SDK build in `build-streamline`. Supplying `nvngx_dlssnr.dll` does not supply that SDK or its DLAA components.

Use the released Setup EXE for automatic NR installation: choose NR on the rendering page, leave DLL fields blank for pinned downloads, or select local NVIDIA-signed DLLs. Setup supplies the matching neural engine, official Streamline plugins, DLSS SR, the NR runtime, consumer add-on and renamed ReShade runtime without a DXGI proxy. Native and DLAA/DLSS profiles disable the compatibility layer. The legacy `Setup-NeuralDoom.ps1 -NRRuntimePath/-NRRuntimeUrl` options are rejected; they did not establish the complete stack. See [the player guide](../PLAYING.md) for upgrade, copy, uninstall and precise F-key controls.

## Optional capture tools

Useful later, not required for the baseline build:

- RenderDoc;
- NVIDIA Nsight Graphics;
- PresentMon or another repeatable frame-time capture tool.

Install capture tools only from their canonical vendor/project sources. Record versions in test results.

`Configure-RBDOOM-DX12.ps1 -Clean` only accepts an existing dedicated build directory inside the repository whose CMake cache matches this source tree. Source, asset and redirected directories are rejected.
