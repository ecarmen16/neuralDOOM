# Install and play neuralDoom

Download the latest installer from [releases](https://github.com/ecarmen16/neuralDOOM/releases/latest). See [known issues](KNOWN_ISSUES.md) for current limitations.

## Install or manage

1. Run **neuralDoom-Setup-<version>.exe**. Setup detects registered and older default/Desktop installations; Browse can find another. Choose **Upgrade / repair**, **Copy to a new folder**, **New installation**, or **Uninstall**.
2. Select the destination and your owned **Doom 3 BFG Edition** installation. Upgrades replace program files in place with a rollback backup; a copy imports saves and settings into a separate folder. Your original BFG data remains unchanged.
3. Choose **NR + DLAA / DLSS**, **DLAA / DLSS**, or **Native RTX**. Leave DLL fields blank for automatic downloads, or select `nvngx_dlss.dll` / `nvngx_dlssnr.dll` locally. DLSS SR must have a valid NVIDIA x64 signature; NR must match the tested RHI 310.8.SF-v2 version. NR downloads the complete pinned compatibility stack, loads ReShade through the engine, and installs no `dxgi.dll` proxy.
4. Review and install. Setup obtains Microsoft prerequisites, verified lighting data, and the chosen neural components. Up to 2.1 GB downloads and about 16 GB free space for a new install; allow 4 GB for an upgrade. No compiler, Git, Python or preinstalled archive tool is required. Windows may request permission for Microsoft prerequisites.
5. Use the Start menu or desktop shortcut. The launcher shows the available rendering profiles and explains their tradeoffs. NR is the fresh-install default; setup and saved **Next Launch Profile** choices select the initial option. Choose a profile and click **Play Doom 3** to enter the Doom 3 menu directly. Setup does not start the game.

**DLAA is native resolution (100%).** Choose reconstruction in the launcher or **System Options > DLAA / DLSS Quality**. Rendering Status shows actual input/output dimensions. Choices persist after a normal game exit. Lighting controls remain available in every profile.

| Mode | Rendering input | Main tradeoff |
|---|---|---|
| NR + DLAA (default) | Native resolution | Experimental neural appearance processing adds cost and can change brightness/detail. F6 compares NR with direct DLAA passthrough. Native HDR is unavailable. |
| NR + DLSS (experimental) | Quality ~67%, Balanced ~58%, Performance ~50% per axis | Explicit choices to reduce engine rendering cost. NR may retain substantial processing cost; compatibility and performance have not yet been measured. F6 preserves the chosen reconstruction. |
| DLAA | Native resolution | NVIDIA anti-aliasing prioritizes edge stability and detail without reducing rendering resolution. Native HDR is available; NR is not loaded. |
| DLSS Quality | About 67% per axis, 44% of native pixels | Upscaling favors detail; may improve FPS when GPU limited. |
| DLSS Balanced | About 58% per axis, 34% of native pixels | Lower rendering cost with more loss of fine detail and stability in motion. |
| DLSS Performance | About 50% per axis, 25% of native pixels | Largest rendering reduction; more visible softness or instability in thin details and motion. |
| Native RTX | Native resolution | Engine TAA without NVIDIA reconstruction/NR; useful for baseline comparisons. Native HDR is available. |

DLSS keeps output resolution and HUD native. The SDK selects exact input dimensions; performance gains depend on the scene and GPU load. Its profile also offers Native TAA for in-game comparison with DLAA. F6 only affects the NR profile. NVIDIA Reflex is not integrated.

**NR requires SDR output**, whether paired with DLAA or DLSS. Native HDR is disabled in the NR profile. Choose **DLAA / DLSS** without NR or **Native RTX** to use native HDR.

Cancel stops between operations and retains verified downloads. A failed upgrade restores replaced application files. Saves and settings remain under `captures/dogfood`; `reshade.ini` appearance controls are preserved. Backups/downloads remain in `.neuraldoom-cache`. Uninstall removes only recorded unchanged application files, keeping saves, settings, modified files and cache. Legacy installs have no full ownership record, so their separately copied game data is retained. Each new installation is listed separately in Windows Installed Apps.

For setup and game log locations, see [reporting a problem](#reporting-a-problem).

Advanced ZIP installation remains available through `Install-InternalTest.cmd -Profile NR` (or `DLAA` / `Native`). Optional `-DlssDllPath`, `-NRDllPath`, `-GamePath` and `-LightingPackPath` avoid manual copying. `-VerifyOnly` performs no downloads or installation. Prefer the EXE for upgrade/copy/uninstall management.

The package contains our native and SDK-enabled engines, compiled shaders and corresponding source. Retail assets, lighting packs, ReShade/RenoDX and NVIDIA runtime DLLs are excluded. Optional components are acquired during setup; sources, hashes and license limitations are recorded in the installed notices and `docs/neural-rendering/THIRD_PARTY_AND_LEGAL.md`.

## Flashlight difficulty

**Game Options > Flashlight Difficulty (SP)** controls the flashlight independently of game difficulty. Normal is the default. Multipliers below are relative to Normal; a larger recharge-time multiplier means a longer wait.

| Level | Battery drain | Recharge time | Beam brightness |
|---|---|---|---|
| Easy | 0.75× | 0.75× | 115% |
| Normal | 1× | 1× | 100% |
| Hard | 1.5× | 2× | 85% |
| Nightmare | 2× | 4× | 70% |

This setting applies to single-player. Classic flashlight mode retains its unlimited battery.

## Settings snapshots and resets

After exiting Doom 3 normally, use **Save snapshot...** in the launcher to save
a ZIP under `settings-snapshots` or another local folder. It captures saved game
configuration/bindings, ReShade/NR configuration and the referenced effects
preset when present, with a checksum manifest. Unsaved launcher selections are
not applied. Savegames, profile progress, runtime DLLs, shaders and screenshots
are excluded. Snapshots export saved settings; automatic snapshot restoration is
not currently supported. Review snapshot contents for local paths before sharing.

Launcher **Restore defaults...** includes ReShade/NR. The independent in-game
**System Options > Restore Game / Video Defaults** resets game/video/audio/controls
while retaining external ReShade settings. Both preserve saves and progress.
Finish a pending reset by launching and exiting before taking a new snapshot.

## Exact comparison controls

These defaults occupy keys unused by the normal game. Custom bindings are preserved. All engine actions below can be remapped in **Settings > Controls > Keyboard Bindings**, under **Renderer Comparisons**. Animated geometry has a bindable action but no extra default key.

| Key | Exactly what it changes |
|---|---|
| F1 | In NR: cycle DLAA → Quality → Balanced → Performance → DLAA. In the SDK-only profile: native-resolution TAA / DLAA; this leaves an upscale preset. No change in Native. |
| F2 | Moving ray geometry on/off: visible opaque doors, props and characters. Does not toggle the four lighting effects or Doomguy's independent body-shadow setting. |
| F3 | RTX material reflections only. |
| F4 | RTX diffuse material bounce only. |
| F5 | Quicksave. |
| F6 | NR on/off in the NR profile; off retains the selected DLAA or DLSS reconstruction. It does not toggle RTX lighting or change the engine preset. The add-on owns this key and its current effect state. |
| F7 | Ray-traced ambient occlusion only. |
| F8 | Ray-traced contact shadows only. |
| F9 | Quickload. |
| F10 | Cycle: scene → AO visibility → contacts → bounce → albedo → reflections → reflection roughness → scene. Enable the corresponding effect to see its diagnostic. |
| F11 | All four lighting effects: if any is on, turn all off; otherwise turn all on. Strengths, ray quality, reconstruction and geometry controls remain unchanged. |
| F12 | Take a Doom screenshot. |
| F13 | Optional NR comparison screenshot pair, if your keyboard/macro pad provides F13. |

System Options also has all four individual lighting toggles, moving/animated geometry, independent reflection/bounce/emissive strengths, Ray Quality, All RTX Lighting, Diagnostic View and Install Free RTX Keys. The latter fills empty keys without replacing custom choices. HDR calibration, HUD/FOV and resolution are in the existing menus. **Doom Lighting Defaults** restores conservative contrast without resetting the rest of your preferences.

**FPS Counter** defaults to **Top right** for fresh settings and follows window resizing, including ultrawide. Toggle it in System Options or use `com_showFPS 1` / `0`; existing saved choices are preserved. **Filmic Intensity** blends the SDR postprocessing effect from 0% (off) to 100% (original effect), in 5% steps. Native HDR bypasses this effect.

**Next Launch Profile** preselects the launcher after quitting/reopening. Native/DLAA/NR initialization is a startup choice. Run setup in Upgrade mode to install omitted neural components. NR status describes the selected compatibility profile, not whether the external add-on is applying its effect. Advanced launches can pass `-NoLauncher` to use saved selections or `-Profile NR -Reconstruction Quality` (also DLAA, Balanced, Performance). `-Profile DLAA` additionally allows TAA. NR defaults to DLAA regardless of an older SDK-only preference; each profile then remembers its own choice. `+set com_startInDoom3 0` restores the classic game selector when launching the engine directly.

## Reporting a problem

Check [known issues](KNOWN_ISSUES.md), then [open an issue](https://github.com/ecarmen16/neuralDOOM/issues) with the version, rendering profile, GPU/driver, resolution, HDR state and steps to reproduce. For visual problems, include the map/location and a screenshot when possible. See [performance reports](neural-rendering/PERFORMANCE_FEEDBACK.md) for slowdowns or stutter.

Setup logs are in `%LOCALAPPDATA%/neuralDoom/SetupLogs` and are linked from the setup result page. Game logs are in the installation's `captures/dogfood/base` directory, named `dogfood-<profile>-<session>.log`. These are the current on-disk names. Attach the log from the affected session and remove private information before sharing.
