# Install and play neuralDoom

Milestone 1 is available from [releases](https://github.com/ecarmen16/neuralDoom/releases/latest). See [known issues](KNOWN_ISSUES.md) for current limitations. Older installers remain available separately.

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

Cancel stops between operations and retains verified downloads. A failed upgrade restores replaced application files. Saves and settings remain under `captures/dogfood`; `reshade.ini` appearance controls are preserved. Backups/downloads remain in `.neuraldoom-cache`. Uninstall removes only recorded unchanged application files, keeping saves, settings, modified files and cache. Legacy installs have no full ownership record, so their separately copied game data is retained. Each new installation is listed separately in Windows Installed Apps.

Setup logs are under local application data in `neuralDoom/SetupLogs`. The progress page offers details and the completion/failure page links to its log. Game launches use unique `captures/dogfood/base/dogfood-<profile>-<session>.log` files and check write access before launch. A failed optional engine log no longer terminates the game.

Advanced ZIP installation remains available through `Install-InternalTest.cmd -Profile NR` (or `DLAA` / `Native`). Optional `-DlssDllPath`, `-NRDllPath`, `-GamePath` and `-LightingPackPath` avoid manual copying. `-VerifyOnly` performs no downloads or installation. Prefer the EXE for upgrade/copy/uninstall management.

The package contains our native and SDK-enabled engines, compiled shaders and corresponding source. Retail assets, lighting packs, ReShade/RenoDX and NVIDIA runtime DLLs are excluded. Optional components are acquired during setup; sources, hashes and license limitations are recorded in the installed notices and `docs/neural-rendering/THIRD_PARTY_AND_LEGAL.md`.

## Exact comparison controls

### Personal settings snapshots and resets

After exiting Doom 3 normally, use **Save snapshot...** in the launcher to save
a ZIP under `settings-snapshots` or another local folder. It captures saved game
configuration/bindings, ReShade/NR configuration and the referenced effects
preset when present, with a checksum manifest. Unsaved launcher selections are
not applied. Savegames, profile progress, runtime DLLs, shaders and screenshots
are excluded. Snapshot files may contain local paths: keep them personal, out
of Git and release packages. This is a save-only export, not an automatic restore
or public baseline-preset feature.

Launcher **Restore defaults...** includes ReShade/NR. The independent in-game
**System Options > Restore Game / Video Defaults** resets game/video/audio/controls
while retaining external ReShade settings. Both preserve saves and progress.
Finish a pending reset by launching and exiting before taking a new snapshot.
Shipped defaults remain unchanged until the maintainer confirms the preferred
settings after a full reset; a later sanitized baseline should omit personal
paths, bindings and progress flags as appropriate.

These defaults occupy keys unused by the normal game. Custom bindings are preserved. All engine actions below can be remapped in **Settings > Controls > Keyboard Bindings**, under **Renderer Comparisons**. Animated geometry has a bindable action but no extra default key.

| Key | Exactly what it changes |
|---|---|
| F1 | In NR: cycle DLAA → Quality → Balanced → Performance → DLAA. In the SDK-only profile: native-resolution TAA / DLAA; this leaves an upscale preset. No change in Native. |
| F2 | Moving ray geometry on/off: visible opaque doors, props and characters. Does not toggle the four lighting effects. |
| F3 | RTX material reflections only. Replaces the old F9 reflection binding. |
| F4 | RTX diffuse material bounce only. |
| F5 | Doom quicksave, unchanged. The add-on's separate screenshot shortcut is moved to F13. |
| F6 | NR on/off in the NR profile; off retains the selected DLAA or DLSS reconstruction. It does not toggle RTX lighting or change the engine preset. The add-on owns this key and its current effect state. |
| F7 | Ray-traced ambient occlusion only. |
| F8 | Ray-traced contact shadows only. |
| F9 | Doom quickload, restored if the old RTX preset had overwritten it. |
| F10 | Cycle: scene → AO visibility → contacts → bounce → albedo → reflections → reflection roughness → scene. Enable the corresponding effect to see its diagnostic. |
| F11 | All four lighting effects: if any is on, turn all off; otherwise turn all on. Strengths, ray quality, reconstruction and geometry controls remain unchanged. |
| F12 | Doom screenshot, unchanged. |
| F13 | Optional NR comparison screenshot pair, if your keyboard/macro pad provides F13. No longer shares F5. |

System Options also has all four individual lighting toggles, moving/animated geometry, independent reflection/bounce/emissive strengths, Ray Quality, All RTX Lighting, Diagnostic View and Install Free RTX Keys. The latter fills empty keys without replacing custom choices. HDR calibration, HUD/FOV and resolution are in the existing menus. **Doom Lighting Defaults** restores conservative contrast without resetting the rest of your preferences.

**FPS Counter** defaults to **Top right** for fresh settings and follows window resizing, including ultrawide. Toggle it in System Options or use `com_showFPS 1` / `0`; existing saved choices are preserved. **Filmic Intensity** blends the SDR postprocessing effect from 0% (off) to 100% (original effect), in 5% steps. Native HDR bypasses this effect.

**Next Launch Profile** preselects the launcher after quitting/reopening. Native/DLAA/NR initialization is a startup choice. Run setup in Upgrade mode to install omitted neural components. NR status describes the selected compatibility profile, not whether the external add-on is applying its effect. Advanced launches can pass `-NoLauncher` to use saved selections or `-Profile NR -Reconstruction Quality` (also DLAA, Balanced, Performance). `-Profile DLAA` additionally allows TAA. NR defaults to DLAA regardless of an older SDK-only preference; each profile then remembers its own choice. `+set com_startInDoom3 0` restores the classic game selector when launching the engine directly.

## Five-minute test

1. Start/load a map. Set your native resolution; verify Rendering Status. Enable Windows HDR before starting if testing native HDR.
2. Compare F3 reflections and F4 bounce near screens/metal floors. Watch for excessive brightness. Compare F7 corners and F8 contact shadows separately.
3. Watch a door or character move; compare F2. Off-screen dynamic objects, glass, particles and the weapon are not included in this pass. Dynamic reflections can be noisier because secondary-hit temporal history is not implemented yet.
4. Scroll the settings and key-binding menus; try mouse and keyboard, FPS Counter and Filmic Intensity. Resize and check the counter stays top-right. Quit/relaunch to confirm settings and launch quality persist. Test F5/F9 only where saving/loading is safe for your current playthrough.
5. Report the ZIP/version, GPU/driver, resolution/HDR state, map/location, exact key or setting, and whether the issue disappears when that feature is off. Include the newest `captures/dogfood/base/dogfood-*.log`; review logs before sharing.
