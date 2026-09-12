# Map lighting data

## Probe and light-grid fallback

`base/_rbdoom_global_illumination_data.pk4` supplies RBDOOM map-specific lighting bakes. Retail BFG data and texture packs do not replace these bakes.

`Game_local.cpp::PopulateEnvironmentProbes` creates probes at valid BSP-area centers when no authored probe entities exist. `R_DeriveEnvprobeData` derives their texture names. `R_FindClosestEnvironmentProbes` uses built-in UAC lobby probes when map textures are absent or defaulted. A loaded placeholder is not a valid lighting texture.

Per-area light grids are independent of view-probe selection. `LoadLightGridImages` skips grids without valid samples, matching the baker. Use the diagnostics below to distinguish missing lighting from empty areas.

## Lighting pack

The upstream [v1.6.0 release](https://github.com/RobertBeckebans/RBDOOM-3-BFG/releases/tag/v1.6.0) provides `RBDOOM-3-BFG-1.6.0.22-full-win64-20250510-git-ba39ba6.7z`. Setup extracts only `base/_rbdoom_global_illumination_data.pk4`. The release executable, shaders and other contents are not installed over this source build.

| Artifact | Size | SHA-256 |
|---|---:|---|
| Official full release archive | 1,647,091,125 bytes | `F1B9A325CEDE2A281ECE7D10A1A8BC48CE760D12AE23E37C62308631A886ABAE` |
| Lighting pack | 1,478,656,988 bytes | `D83D1D1D4F9F72D4DC1B8F7870BC0C379ADEEE5A405C2AB1FE4308851FBB303F` |

These are measured fingerprints of the official HTTPS download, not a publisher-signed checksum claim. ZIP CRC validation passed for every pack entry. The pack contains 12,150 `.bimage` textures, 47 `.blightgrid` files and 47 `.lightgrid` files, with no executable entries or unsafe paths. Content remains local and ignored by Git; its inclusion in an upstream archive does not authorize bundling it into neuralDoom releases.

For another installation, extract that single pack from the official archive into a temporary directory and copy it to the game checkout's `base/` directory. Preserve any existing pack until its identity is checked. Restart the game so its virtual filesystem loads the pack, then verify a loaded map with the commands below. A mod that changes geometry or probe placement can require different bakes.

Avoid running `bakeEnvironmentProbes` blindly as a repair command: it processes all map probes, performs expensive CPU convolution and writes to `fs_basepath`, even when screenshots/saves use an isolated `fs_savepath`. It also alters several renderer settings while baking.

## Diagnostics

```text
probeLightingStatus
rayTracingStatus
```

`probeLightingStatus` waits for the game thread and reads existing CPU-side state. It reports world/map, probe counts, complete pairs, defaulted/unloaded images, per-area light-grid availability and selected probe image names/weights. Grids with no valid samples are counted as `empty`, independently of missing images in populated grids. `PROBE_SELECTION` counts both all fallback specular slots and only slots with positive blending weight. This is an on-demand audit, not a new per-frame pass, texture loader or change to selection behavior. Calling it before a map is loaded reports `world=0` safely.

`rayTracingStatus` queries NVRHI's device capabilities and separately reports `sceneImplemented=0`. Hardware capability is not evidence of ray-traced lighting.

Setup and prerequisite reports use `Get-NeuralLightingData.ps1` to flag absent lighting candidates. Presence of a nonempty pack with the expected filename or loose EXR/bimage files is inventory only; it does not establish validity, complete map coverage or the active mod's search-path precedence. Runtime diagnostics provide that evidence.

```powershell
.\tools\neural-rendering\Get-NeuralLightingData.ps1 -RepoRoot .
.\tools\neural-rendering\Test-NeuralDoom-Smoke.ps1 -GpuProfile -Width 2560 -Height 720 -WarmupFrames 600 -Frames 64 -ExpectedProbeLighting Local
```

The smoke runner records probe/light-grid state and RT capabilities in `result.json`. `-ExpectedProbeLighting Local` requires complete map probe pairs and an active local selection; `Fallback` requires missing map pairs and built-in selection. The default `Any` records either state. Neither assertion certifies artistic quality or lighting coverage of every room.
