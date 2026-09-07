# neuralDoom internal RTX test build

## Install once

1. Run **neuralDoom-Setup-<version>.exe**. The dark Windows wizard guides you through Welcome, Install Location, Ready to Install, Installation, and Complete. Click Next to use the suggested versioned location or browse to a separate empty folder.
2. On Install Location, confirm the detected Steam BFG folder or browse to your owned **Doom 3 BFG Edition** folder. Choose whether to create a desktop shortcut. No manual lighting download or extraction is needed.
3. Setup installs Microsoft's runtime if missing (Windows may ask for administrator approval), downloads the official RBDOOM lighting archive and a pinned standalone extraction tool, verifies their hashes, and extracts only the required lighting pack. The lighting download is approximately 1.65 GB; verified cached downloads are reused on retry.
4. Setup copies missing owned game data and validates the installed Release build. Its progress page stays responsive, with optional details. Finish offers your installation folder, setup log, and test controls. Start the game from the **neuralDoom Internal Test** Start menu entry or optional desktop shortcut. The game is not launched automatically.

Cancel during installation requests a stop after the current operation; it does not kill a prerequisite installer or interrupt a file copy. Verified downloads remain available for Retry. Failures stay in the wizard, with a View Setup Log button; logs are saved under local application data in `neuralDoom/SetupLogs`. Progress indicates the current operation without estimating a misleading overall percentage. Windows prerequisite permission prompts can still appear separately.

No compiler, Git, Python, preinstalled 7-Zip, or separately collected supporting files are required. Keep roughly 15 GB free for the installation and download cache. The first setup requires internet; choosing the destination, Windows security/prerequisite approval and locating an undetected owned game are the manual steps. Saves/settings are in the installed folder's `captures/dogfood` directory. Choose a new empty folder for a later version to preserve the previous installation and its saves. Noninteractive bootstrap calls without an explicit destination use a versioned folder under local application data.

The ZIP remains available as an alternative: extract it and run Install-InternalTest.cmd. The same automatic downloads run there. Advanced/offline setup can pass `-GamePath` and `-LightingPackPath` explicitly. `-VerifyOnly` performs no downloads or installation.

The internal ZIP is native RTX/TAA. It contains no retail data, lighting pack, mods, DLAA SDK binaries, ReShade, RenoDX or NR runtime. DLAA/NR remain separate local development profiles; selecting a menu option cannot install them. No Python, Git, compiler or Visual Studio is needed to install/play this ZIP.

## Exact comparison controls

These defaults occupy keys unused by the normal game. Custom bindings are preserved. All engine actions below can be remapped in **Settings > Controls > Keyboard Bindings**, under **Renderer Comparisons**. Animated geometry has a bindable action but no extra default key.

| Key | Exactly what it changes |
|---|---|
| F1 | Native-resolution TAA / DLAA, only in a supported local DLAA profile. No change in the native test ZIP or NR profile. |
| F2 | Moving ray geometry on/off: visible opaque doors, props and characters. Does not toggle the four lighting effects. |
| F3 | RTX material reflections only. Replaces the old F9 reflection binding. |
| F4 | RTX diffuse material bounce only. |
| F5 | Doom quicksave, unchanged. |
| F6 | Reserved for the external NR add-on in the local NR profile. No NR action in the internal ZIP. The engine cannot report or remap the add-on's private toggle. |
| F7 | Ray-traced ambient occlusion only. |
| F8 | Ray-traced contact shadows only. |
| F9 | Doom quickload, restored if the old RTX preset had overwritten it. |
| F10 | Cycle: scene → AO visibility → contacts → bounce → albedo → reflections → reflection roughness → scene. Enable the corresponding effect to see its diagnostic. |
| F11 | All four lighting effects: if any is on, turn all off; otherwise turn all on. Strengths, ray quality, reconstruction and geometry controls remain unchanged. |
| F12 | Doom screenshot, unchanged. |

System Options also has all four individual lighting toggles, moving/animated geometry, independent reflection/bounce/emissive strengths, Ray Quality, All RTX Lighting, Diagnostic View and Install Free RTX Keys. The latter fills empty keys without replacing custom choices. HDR calibration, HUD/FOV and resolution are in the existing menus. **Doom Lighting Defaults** restores conservative contrast without resetting the rest of your preferences.

**Next Launch Profile** is used by the local development launchers after quitting/reopening. Native/DLAA/NR initialization is a startup choice, not a safe mid-frame switch. The internal Play launcher deliberately selects its included Native Release build. NR status describes the selected compatibility profile, not whether the external add-on is currently applying its effect.

## Five-minute test

1. Start/load a map. Set your native resolution; verify Rendering Status. Enable Windows HDR before starting if testing native HDR.
2. Compare F3 reflections and F4 bounce near screens/metal floors. Watch for excessive brightness. Compare F7 corners and F8 contact shadows separately.
3. Watch a door or character move; compare F2. Off-screen dynamic objects, glass, particles and the weapon are not included in this pass. Dynamic reflections can be noisier because secondary-hit temporal history is not implemented yet.
4. Scroll the settings and key-binding menus; try mouse and keyboard. Quit/relaunch to confirm settings persist. Test F5/F9 only where saving/loading is safe for your current playthrough.
5. Report the ZIP/version, GPU/driver, resolution/HDR state, map/location, exact key or setting, and whether the issue disappears when that feature is off. Include `captures/dogfood/base/dogfood-Native.log`; review logs before sharing.

## Maintainer packaging

Commit source, synchronize the local build checkout to that exact commit, configure DX12 with `-RayTracing ON` and SDK off, then run `Build-RBDOOM.ps1 -Configuration Release -BuildDirectory <native-build-rt>`. From a Python 3 environment:

```text
python tools/neural-rendering/Build-InternalPackage.py --source <clean-source-checkout> --game <matching-build-checkout> --output <new-output.zip>
```

The packager requires clean matching commits, initialized pinned submodules, a Release/native-RTX manifest, matching EXE/shaders and no debug CRT/NVIDIA imports. It includes Git-tracked source and recursive submodule source, omits unused upstream prebuilt tools/import libraries, and rejects DLLs, PDBs, retail resources and PK4s. It never recursively copies the game folder. The ZIP has a SHA-256 sidecar and `internal-package.json` hashes; the installer converts portable build identity only after verification. Unsigned test builds may prompt through Windows SmartScreen; the hash establishes artifact identity, not publisher signing.

Source rebuild instructions and license notices remain in README.md, LICENSE.md, LICENSE_EXCEPTIONS.md, COPYING.txt where present, and dependency source directories. Optional upstream prebuilt tools omitted from the ZIP are not required by the documented DX12/FFMPEG-off/XAudio build. The included source has expanded submodules; a Git clone should use `--recursive` instead.

When rebuilding directly from the exported source without Git metadata, use the documented CMake configure options and `cmake --build build-rt --config Release`. The Build-RBDOOM manifest helper requires a Git checkout; the raw CMake build does not create launcher identity files.

To wrap the verified ZIP as the single-file setup:

```powershell
.\tools\neural-rendering\Build-InternalSetup.ps1 -PackagePath <package.zip> -OutputPath <new-setup.exe>
```

This uses the Windows .NET Framework compiler and embeds the ZIP plus its matching bootstrap source. `setup.exe --verify` validates/extracts the embedded payload in a temporary folder without installing, downloading or launching the game. The EXE also has a SHA-256 sidecar. Publisher sources: [RBDOOM release](https://github.com/RobertBeckebans/RBDOOM-3-BFG/releases/tag/v1.6.0), [7-Zip downloads](https://www.7-zip.org/download.html), [Microsoft runtime](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).
