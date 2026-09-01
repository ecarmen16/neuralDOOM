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

Then run `02-INSTALL-ISPC.cmd`. The helper accepts an `ispc.exe` or ZIP and installs it at:

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

Steam libraries may be elsewhere. Run `03-COPY-GAME-DATA.cmd` and select the actual `base` directory.

## Optional capture tools

Useful later, not required for the baseline build:

- RenderDoc;
- NVIDIA Nsight Graphics;
- PresentMon or another repeatable frame-time capture tool.

Install capture tools only from their canonical vendor/project sources. Record versions in test results.
