# Map lighting data investigation

Reviewed 2026-09-06 on `codex/probe-lighting`, starting at `5ca342cf`.

## Cause and existing fallback

The local installation was missing RBDOOM's optional `base/_rbdoom_global_illumination_data.pk4`. Retail BFG resources and D3HDP were present, but neither supplied the expected map-specific RBDOOM lighting bakes in the baseline profile.

`Game_local.cpp::PopulateEnvironmentProbes` creates probes at valid BSP-area centers when a map has no authored probe entities. `RenderWorld_defs.cpp::R_DeriveEnvprobeData` derives diffuse/specular image names from the map, area and snapped origin. For `maps/game/mars_city2.map`, 98 probes request 196 distinct textures. The previous baseline log prints 392 missing-image lines because the warning list is repeated; this is 196 missing images, not 392 separate assets.

`tr_frontend_main.cpp::R_FindClosestEnvironmentProbes` already checks loaded/nondefaulted irradiance and defaulted radiance. When map textures are absent it selects the UAC lobby probes compiled into `Image_intrinsic.cpp`, and clears local parallax bounds when all selected specular probes fall back. `IsLoaded()` alone is insufficient: a missing image's allocated placeholder is loaded but defaulted. The first runtime diagnostic confirmed 98 probes, zero complete pairs, 196 defaulted images, and zero unloaded images. No fallback shader or brightness change was needed.

Light grids are a separate diffuse-lighting source. `RenderWorld_lightgrid.cpp::SetupLightGrid/LoadLightGridImages` and `RenderBackend.cpp::DrawSingleInteraction` can use per-area grids independently of the selected view probe. The diagnostic reports their image availability separately; a view's probe selection does not prove which diffuse source every surface used.

Restoring the pack exposed a smaller loader mismatch: `bakeLightGrids` skips areas with zero valid samples, but `LoadLightGridImages` previously requested an atlas for every area. Mars City 2 has nine zero-point areas and two areas containing only an invalid placeholder point (0 and 103). The loader now uses the same `CountValidGridPoints() == 0` condition as the baker and leaves their image pointers null. Existing frontend checks in `tr_frontend_addmodels.cpp` preserve probe fallback for those areas. Missing atlases in areas with valid samples still load normally and report their warnings. No sampling, grid coordinates, resource formats or per-frame shader behavior changed.

## Official local content

The upstream [v1.6.0 release](https://github.com/RobertBeckebans/RBDOOM-3-BFG/releases/tag/v1.6.0) provides `RBDOOM-3-BFG-1.6.0.22-full-win64-20250510-git-ba39ba6.7z`. Only its `base/_rbdoom_global_illumination_data.pk4` was extracted for this task. The release executable, shaders and other contents are not installed over this source build.

| Artifact | Size | Locally measured SHA-256 |
|---|---:|---|
| Official full release archive | 1,647,091,125 bytes | `F1B9A325CEDE2A281ECE7D10A1A8BC48CE760D12AE23E37C62308631A886ABAE` |
| Lighting pack | 1,478,656,988 bytes | `D83D1D1D4F9F72D4DC1B8F7870BC0C379ADEEE5A405C2AB1FE4308851FBB303F` |

These are measured fingerprints of the official HTTPS download, not a publisher-signed checksum claim. ZIP CRC validation passed for every pack entry. The pack contains 12,150 `.bimage` textures, 47 `.blightgrid` files and 47 `.lightgrid` files, with no executable entries or unsafe paths. All 196 exact missing Mars City 2 image names exist in it. Content remains local and ignored by Git; its inclusion in an upstream archive does not authorize bundling it into neuralDoom releases.

For another installation, extract that single pack from the official archive into a temporary directory and copy it to the game checkout's `base/` directory. Preserve any existing pack until its identity is checked. Restart the game so its virtual filesystem loads the pack, then verify a loaded map with the commands below. A mod that changes geometry or probe placement can require different bakes.

Avoid running `bakeEnvironmentProbes` blindly as a repair command: it processes all map probes, performs expensive CPU convolution and writes to `fs_basepath`, even when screenshots/saves use an isolated `fs_savepath`. It also alters several renderer settings while baking. A bounded, isolated bake workflow remains future work for changed maps.

## Diagnostics

```text
probeLightingStatus
rayTracingStatus
```

`probeLightingStatus` waits for the game thread and reads existing CPU-side state. It reports world/map, probe counts, complete pairs, defaulted/unloaded images, per-area light-grid availability and selected probe image names/weights. Grids with no valid samples are counted as `empty`, independently of missing images in populated grids. `PROBE_SELECTION` counts both all fallback specular slots and only slots with positive blending weight. This is an on-demand audit, not a new per-frame pass, texture loader or change to selection behavior. Calling it before a map is loaded reports `world=0` safely.

`rayTracingStatus` queries NVRHI's device capabilities and separately reports `sceneImplemented=0`. Hardware capability is not evidence of ray-traced lighting. See [RAY_TRACING_PLAN.md](archive/RAY_TRACING_PLAN.md) for the staged implementation plan.

Setup and prerequisite reports use `Get-NeuralLightingData.ps1` to flag absent lighting candidates. Presence of a nonempty pack with the expected filename or loose EXR/bimage files is inventory only; it does not establish validity, complete map coverage or the active mod's search-path precedence. Runtime diagnostics provide that evidence.

```powershell
.\tools\neural-rendering\Get-NeuralLightingData.ps1 -RepoRoot .
.\tools\neural-rendering\Test-NeuralDoom-Smoke.ps1 -GpuProfile -Width 2560 -Height 720 -WarmupFrames 600 -Frames 64 -ExpectedProbeLighting Local
```

The smoke runner records probe/light-grid state and RT capabilities in `result.json`. `-ExpectedProbeLighting Local` requires complete map probe pairs and an active local selection; `Fallback` requires missing map pairs and built-in selection. The default `Any` records either state. Neither assertion certifies artistic quality or lighting coverage of every room.

## Validation record

Runtime/build results are recorded in the dated entry in [TEST_RESULTS.md](archive/TEST_RESULTS.md). The earlier [LIGHTING_BASELINE.md](archive/LIGHTING_BASELINE.md) measures the missing-pack state and must retain that qualification when comparing future lighting work.
