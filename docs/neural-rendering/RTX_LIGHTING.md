# Full-resolution RTX material lighting

**2026-09-06 reflection update:** Full-resolution rough reflections now use the native material response and replace matched probe specular. Default GI strength is 1.125, down 25%. See [reflection controls, contracts and the three-check playtest](RAY_TRACED_REFLECTIONS.md). GPU validation of this addition remains with the user.

`Launch-NeuralDoom-RTX.cmd` enables reflections, material bounce, contact shadows and AO. It supports Native and optional DLAA rendering, with native HDR output when Windows HDR is enabled. `Launch-NeuralDoom.cmd` preserves saved feature choices. Both select the exact CMake output and verify its build manifest. No ReShade bridge is required.

## Subdued lighting preset

For the 2026-09-07 brightness feedback, `exec neural_rtx_contrast.cfg` applies fixed exposure, ambient **0.375**, diffuse bounce strength **1.125**, and reflection blend **0.65**. These now match the conservative factory starting values; existing archived settings need the one-time in-game preset to adopt them. It preserves HDR calibration, AO, contacts, ray samples and render resolution. Lower reflection blend restores more native probe specular, so it does not imply a uniform 35% darker image. The earlier offline config reset did not remain in the latest saved config; apply this inside the game and exit normally. See [SETTINGS_REVIEW.md](SETTINGS_REVIEW.md) for the exposure bug and full audit.

The active local `reshade.ini` NR section was reset by removing its saved tuning overrides so the installed add-on supplies its own defaults. Only NR enabled and upscaling disabled remain explicit, retaining full-resolution rendering. Other ReShade sections and earlier backups were preserved. This is distinct from setting every tuning slider to 1, which would not necessarily match the add-on's defaults.

## Controls

Direct edits to any RTX cvar now reset temporal history on the next primary view, including intensity, radius, samples and debug mode. A separate `neuralHistoryReset` is optional.

Open the console and run `exec neural_rtx_keys.cfg` to install the example bindings. The file is editable; use preferred key or mouse-button names. It is not executed automatically over existing bindings.

| Key | Action |
|---|---|
| F4 | Toggle material bounce lighting |
| F6 | Toggle NR in the NR launcher profile (handled by the installed add-on) |
| F7 | Toggle ray-traced AO |
| F8 | Toggle contact shadows |
| F9 | Toggle material reflections |
| F10 | Cycle scene, AO, contacts, bounce, albedo, reflections and reflection roughness |
| F11 | Toggle all four RTX effects together |

Each binding resets temporal history. For example: `bind F4 "toggle r_rayTracedGI; neuralHistoryReset"`. `rayTracingToggle` and `rayTracingDebugCycle` are also directly bindable commands.

| Cvar | Default | Range / purpose |
|---|---:|---|
| `r_rayTracedReflections` | 0 | 0/1: full-resolution material reflections |
| `r_rayTracedReflectionStrength` | 0.65 | 0-1: blend native probe specular toward ray hits |
| `r_rayTracedReflectionSamples` | 4 | 1-16 rays per eligible full-resolution pixel |
| `r_rayTracedReflectionRoughness` | 0.7 | 0.1-1: upper roughness limit; fades over the final 0.15 |
| `r_rayTracedReflectionDistance` | 2048 | 16-8192 world units |
| `r_rayTracedGI` | 0 | 0/1: full-resolution diffuse bounce and color bleeding |
| `r_rayTracedGIStrength` | 1.125 | 0–4: bounce intensity |
| `r_rayTracedGISamples` | 4 | 1–16 rays per full-resolution pixel |
| `r_rayTracedGIRadius` | 384 | 16–2048: maximum bounce distance, world units |
| `r_rayTracedGIEmissive` | 2 | 0–8: supported emissive material contribution |
| `r_rayTracedContactShadows` | 0 | 0/1: additional short-range direct-light visibility |
| `r_rayTracedContactDistance` | 128 | 1–512 world units |
| `r_rayTracedContactStrength` | 1 | 0–1 |
| `r_rayTracedAO` | 0 | 0/1, requires SSAO and the new SSAO pass |
| `r_rayTracedAOStrength` | 1 | 0–2 |
| `r_rayTracedAOSamples` | 8 | 1–32 hemisphere rays |
| `r_rayTracedAORadius` | 64 | 1–256 world units |
| `r_rayTracingDebug` | 0 | 0 scene; 1 AO; 2 contacts; 3 bounce lighting only; 4 diffuse albedo; 5 reflections; 6 reflection roughness |

Use F9 near glossy metal panels or a polished floor, then F10 to isolate reflections. Use F4 to judge diffuse bounce separately. The lower GI default preserves more of Doom 3's dark-room contrast. Existing saved profiles retain their intensity unless changed; use `r_rayTracedGIStrength 1.125` to adopt the new default.

## Implementation and limits

`RayTracingDiagnostic.cpp::RayTracedLighting` builds a static opaque BSP ray scene with per-vertex UVs and material indices. A GPU-only array caches 256×256 texture tiles for the first supported diffuse and additive emissive stage per material. Diffuse sampling uses the native YCoCg and sRGB-to-linear conversions. Material colors, conditions and UV transforms are evaluated each frame with the static world shader parameters.

Every output pixel traces its own primary receiver and cosine-weighted diffuse bounce rays. At visible ray hits, a pre-GI HDR snapshot supplies the renderer's complete material radiance, including native probe lighting and normal maps. Reprojection requires depth agreement. Offscreen/occluded hits evaluate textured diffuse/emissive materials and up to 16 current-view point/projected light stages with their actual projection/falloff textures, colors, texture transforms and shadow visibility rays. A short edge fade blends the visible cache with explicit lighting. The snapshot precedes GI, preventing recursive feedback. This is a hybrid single-bounce estimate; the view-dependent cache and limited light list can change as the camera turns.

`RayTracedContacts` snapshots HDR before each eligible light and attenuates only that light's opaque contribution afterward. It respects shadow-caster material flags, skips parallel lights, and retains raster shadows. A full-resolution R8 visibility image supports comparison. Copying HDR requires invalidating both the engine graphics cache and NVRHI's cached framebuffer binding; native DX12 validation caught and verified the fix for this requirement.

All rays currently intersect static opaque BSP geometry. Moving entities, the weapon, cutouts, glass, custom programs, video/GUI emission and blended vertex-color materials are not fully represented. Raster-depth agreement rejects unsupported primary receivers. Geometry normals are used for explicit offscreen lighting; the visible radiance cache includes native normal-map shading. Rough-specular reflections are described in [RAY_TRACED_REFLECTIONS.md](RAY_TRACED_REFLECTIONS.md); dynamic acceleration structures and a full path tracer remain future work. Four fixed rays can produce directional sampling artifacts; sample count is adjustable. Visual motion review remains a user playtest item.

Bounce, radiance snapshot and HDR composition use linear `RGBA16_FLOAT`. Rays and bounce output run at the full viewport resolution, including 5120×1440; there is no half-resolution mode. A 3×3 depth-aware filter operates at full resolution and excludes rejected primary receivers. Existing TAA/DLAA follows the pass, then HDR tone mapping and HUD. Texture-cache resolution is independent of render resolution. Feature-off and RT-compiled-out paths allocate no new ray resources.

`R_ClearRayTracedAO` also releases contacts, material lighting and debug caches on level changes and shutdown. Resize rebuilds bindings and viewport textures. Unsupported APIs/devices, MSAA, subviews and irradiance captures skip these optional passes; initialization failure retains raster rendering for the map.

## Short playtest

1. Launch RTX, select Native or DLAA, and load a save near colored lighting or a lit wall/corner. Install the example bindings once.
2. Toggle F9 near reflective metal, then F4 to isolate diffuse bounce. Use F10 for reflection/roughness views; return it to scene mode for normal play.
3. Walk past a doorway, rotate, fire, and resize or use 5120×1440 borderless. Check for trails, light leaks and stable HUD/FOV. F11 provides immediate rollback.

Diagnostics: `rayTracingReflectionStatus`, `rayTracingGIStatus`, `rayTracingContactStatus`, `rayTracingAOStatus`, `hdrStatus`. GPU coverage counters prove actual work, not subjective visual quality or hardware-independent performance. Build/runtime evidence is in `TEST_RESULTS.md`.

The contrast preset now also selects fixed exposure and ambient 0.375. See [SETTINGS_REVIEW.md](SETTINGS_REVIEW.md) for the exposure correction, saved-setting migration and Material SSR scope.
