# neuralDoom internal RTX test build

## Install or manage

1. Run **neuralDoom-Setup-<version>.exe**. Setup detects registered and older default/Desktop installations; Browse can find another. Choose **Upgrade / repair**, **Copy to a new folder**, **New installation**, or **Uninstall**.
2. Select the destination and your owned **Doom 3 BFG Edition** installation. Upgrades replace program files in place with a rollback backup; a copy imports saves and settings into a separate folder. Your original BFG data remains unchanged.
3. Choose **NR + DLAA**, **DLAA / DLSS**, or **Native RTX**. Leave DLL fields blank for automatic downloads, or select `nvngx_dlss.dll` / `nvngx_dlssnr.dll` locally. Local DLLs must be x64 with a valid NVIDIA signature. NR downloads the complete pinned compatibility stack, loads ReShade through the engine, and installs no `dxgi.dll` proxy.
4. Review and install. Setup obtains Microsoft prerequisites, verified lighting data, and the chosen neural components. Up to 2.1 GB downloads and about 16 GB free space for a new install; allow 4 GB for an upgrade. No compiler, Git, Python or preinstalled archive tool is required. Windows may request permission for Microsoft prerequisites.
5. Use the Start menu or desktop shortcut. Setup does not start the game. Its renderer selection applies on the first launch; afterward **Next Launch Profile** in System Options controls the same shortcut.

**DLAA is native resolution (100%).** In the DLAA/DLSS profile, System Options > Reconstruction cycles Native TAA, DLAA, DLSS Quality, Balanced and Performance. The last three ask the SDK for input dimensions (approximately 67%, 58% and 50% per axis), preserving output resolution and HUD sharpness. Rendering Status shows actual input/output dimensions. Choices persist across launches. The experimental NR profile keeps full-resolution DLAA input and SDR compatibility output; F6 switches NR on/off. Native HDR is available outside the NR profile.

Cancel stops between operations and retains verified downloads. A failed upgrade restores replaced application files. Saves and settings remain under `captures/dogfood`; `reshade.ini` appearance controls are preserved. Backups/downloads remain in `.neuraldoom-cache`. Uninstall removes only recorded unchanged application files, keeping saves, settings, modified files and cache. Legacy installs have no full ownership record, so their separately copied game data is retained. Each new installation is listed separately in Windows Installed Apps.

Setup logs are under local application data in `neuralDoom/SetupLogs`. The progress page offers details and the completion/failure page links to its log. Game launches use unique `captures/dogfood/base/dogfood-<profile>-<session>.log` files and check write access before launch. A failed optional engine log no longer terminates the game.

Advanced ZIP installation remains available through `Install-InternalTest.cmd -Profile NR` (or `DLAA` / `Native`). Optional `-DlssDllPath`, `-NRDllPath`, `-GamePath` and `-LightingPackPath` avoid manual copying. `-VerifyOnly` performs no downloads or installation. Prefer the EXE for upgrade/copy/uninstall management.

The package contains our native and SDK-enabled engines, compiled shaders and corresponding source. Retail assets, lighting packs, ReShade/RenoDX and NVIDIA runtime DLLs are excluded. Optional components are acquired during setup; sources, hashes and license limitations are recorded in the installed notices and `docs/neural-rendering/THIRD_PARTY_AND_LEGAL.md`.

## Exact comparison controls

These defaults occupy keys unused by the normal game. Custom bindings are preserved. All engine actions below can be remapped in **Settings > Controls > Keyboard Bindings**, under **Renderer Comparisons**. Animated geometry has a bindable action but no extra default key.

| Key | Exactly what it changes |
|---|---|
| F1 | Native-resolution TAA / DLAA in the DLAA/DLSS profile. Using F1 leaves a DLSS upscale preset. No change in Native or NR. |
| F2 | Moving ray geometry on/off: visible opaque doors, props and characters. Does not toggle the four lighting effects. |
| F3 | RTX material reflections only. Replaces the old F9 reflection binding. |
| F4 | RTX diffuse material bounce only. |
| F5 | Doom quicksave, unchanged. |
| F6 | NR on/off in the NR profile; off is full-resolution DLAA passthrough. It does not toggle the RTX lighting. The add-on owns this key and its current effect state. |
| F7 | Ray-traced ambient occlusion only. |
| F8 | Ray-traced contact shadows only. |
| F9 | Doom quickload, restored if the old RTX preset had overwritten it. |
| F10 | Cycle: scene → AO visibility → contacts → bounce → albedo → reflections → reflection roughness → scene. Enable the corresponding effect to see its diagnostic. |
| F11 | All four lighting effects: if any is on, turn all off; otherwise turn all on. Strengths, ray quality, reconstruction and geometry controls remain unchanged. |
| F12 | Doom screenshot, unchanged. |

System Options also has all four individual lighting toggles, moving/animated geometry, independent reflection/bounce/emissive strengths, Ray Quality, All RTX Lighting, Diagnostic View and Install Free RTX Keys. The latter fills empty keys without replacing custom choices. HDR calibration, HUD/FOV and resolution are in the existing menus. **Doom Lighting Defaults** restores conservative contrast without resetting the rest of your preferences.

**Next Launch Profile** controls the installed shortcut after quitting/reopening. Native/DLAA/NR initialization is a startup choice. Run setup in Upgrade mode to install a neural component set omitted during the initial install. NR status describes the selected compatibility profile, not whether the external add-on is currently applying its effect.

## Five-minute test

1. Start/load a map. Set your native resolution; verify Rendering Status. Enable Windows HDR before starting if testing native HDR.
2. Compare F3 reflections and F4 bounce near screens/metal floors. Watch for excessive brightness. Compare F7 corners and F8 contact shadows separately.
3. Watch a door or character move; compare F2. Off-screen dynamic objects, glass, particles and the weapon are not included in this pass. Dynamic reflections can be noisier because secondary-hit temporal history is not implemented yet.
4. Scroll the settings and key-binding menus; try mouse and keyboard. Quit/relaunch to confirm settings persist. Test F5/F9 only where saving/loading is safe for your current playthrough.
5. Report the ZIP/version, GPU/driver, resolution/HDR state, map/location, exact key or setting, and whether the issue disappears when that feature is off. Include the newest `captures/dogfood/base/dogfood-*.log`; review logs before sharing.

## Maintainer packaging

Commit source, synchronize the local build checkout to that exact commit, configure DX12 with `-RayTracing ON` and SDK off, then run `Build-RBDOOM.ps1 -Configuration Release -BuildDirectory <native-build-rt>`. From a Python 3 environment:

```text
python tools/neural-rendering/Build-InternalPackage.py --source <clean-source-checkout> --game <matching-build-checkout> --output <new-output.zip> --build-directory <native-release-build> --neural-build-directory <neural-release-build>
```

The packager requires clean matching commits, initialized pinned submodules, a Release/native-RTX manifest, matching EXE/shaders and no debug CRT imports. Native must be SDK-free; the optional second engine must use the same source and shaders with Streamline enabled. It includes Git-tracked source and recursive submodule source, omits unused upstream prebuilt tools/import libraries, and rejects DLLs, PDBs, retail resources and PK4s. It never recursively copies the game folder. The ZIP has a SHA-256 sidecar and `internal-package.json` hashes; the installer converts portable build identity only after verification. Unsigned test builds may prompt through Windows SmartScreen; the hash establishes artifact identity, not publisher signing.

Release diagnostic strings must not embed a personal profile path. Build from a
neutral source location; on Windows, an unused temporary `subst` drive can map
the source checkout while configuring and building a fresh `build-private-release`
tree. Keep that mapping active through packaging and remove it afterward. Pass
`--build-directory <release-build-directory>` when packaging this alternate tree.
The packager rejects personal profile paths in every payload entry, including
ASCII and UTF-16 strings inside binaries. This does not replace a license or
secret review.

Source rebuild instructions and license notices remain in README.md, LICENSE.md, LICENSE_EXCEPTIONS.md, COPYING.txt where present, and dependency source directories. Optional upstream prebuilt tools omitted from the ZIP are not required by the documented DX12/FFMPEG-off/XAudio build. The included source has expanded submodules; a Git clone should use `--recursive` instead.

When rebuilding directly from the exported source without Git metadata, use the documented CMake configure options and `cmake --build build-rt --config Release`. The Build-RBDOOM manifest helper requires a Git checkout; the raw CMake build does not create launcher identity files.

To wrap the verified ZIP as the single-file setup:

```powershell
.\tools\neural-rendering\Build-InternalSetup.ps1 -PackagePath <package.zip> -OutputPath <new-setup.exe>
```

This uses the Windows .NET Framework compiler and embeds the ZIP plus its matching bootstrap source. `setup.exe --verify` validates/extracts the embedded payload in a temporary folder without installing, downloading or launching the game. The EXE also has a SHA-256 sidecar. Publisher sources: [RBDOOM release](https://github.com/RobertBeckebans/RBDOOM-3-BFG/releases/tag/v1.6.0), [7-Zip downloads](https://www.7-zip.org/download.html), [Microsoft runtime](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).
