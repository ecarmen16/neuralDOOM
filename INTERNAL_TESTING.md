# neuralDoom internal RTX test build

## Install once

1. Extract the entire internal-test ZIP into a new writable folder (not your retail game folder). Keep the included source and notices with the build when sharing it.
2. Install the [Microsoft Visual C++ x64 Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe) if needed. Windows 10/11 x64 and a DX12 ray-query-capable GPU are required for RTX effects.
3. From the [official RBDOOM 1.6.0 full release](https://github.com/RobertBeckebans/RBDOOM-3-BFG/releases/tag/v1.6.0), extract `base/_rbdoom_global_illumination_data.pk4`. You also need your own Doom 3 **BFG Edition** installation.
4. Double-click **Install-InternalTest.cmd**. Select the lighting pack and your BFG folder. Setup verifies the package, copies missing local game data, and checks the exact Release EXE and shaders. It does not start the game.
5. Double-click **Play-InternalTest.cmd**. Choose your resolution and HDR settings in System Options. All ray effects start enabled on first use; later choices persist. Saves/settings live in `captures/dogfood` inside this extracted folder.

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
