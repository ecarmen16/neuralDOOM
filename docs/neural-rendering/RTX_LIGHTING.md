# Full-resolution RTX material lighting

**2026-09-06 review:** Native RT, DLAA + RT and RT-OFF builds pass, including the albedo debug view and motion/history fixes. The user will perform visual comparisons; these final changes have not had a new gameplay run. See [the review and short checklist](REVIEW_2026-09-06.md).

`Launch-NeuralDoom-RTX.cmd` enables material bounce, contact shadows and AO. It supports Native and optional DLAA rendering, with native HDR output when Windows HDR is enabled. `Launch-NeuralDoom.cmd` preserves saved feature choices. Both select the exact CMake output and verify its build manifest. No ReShade bridge is required.

## Controls

Direct edits to any RTX cvar now reset temporal history on the next primary view, including intensity, radius, samples and debug mode. A separate `neuralHistoryReset` is optional.

Open the console and run `exec neural_rtx_keys.cfg` to install the example bindings. The file is editable; use preferred key or mouse-button names. It is not executed automatically over existing bindings.

| Key | Action |
|---|---|
| F6 | Toggle material bounce lighting |
| F7 | Toggle ray-traced AO |
| F8 | Toggle contact shadows |
| F10 | Cycle normal scene, AO visibility, contact visibility, material bounce only, material albedo |
| F11 | Toggle all three RTX effects together |

Each binding resets temporal history. For example: `bind F6 "toggle r_rayTracedGI; neuralHistoryReset"`. `rayTracingToggle` and `rayTracingDebugCycle` are also directly bindable commands.

| Cvar | Default | Range / purpose |
|---|---:|---|
| `r_rayTracedGI` | 0 | 0/1: full-resolution diffuse bounce and color bleeding |
| `r_rayTracedGIStrength` | 1.5 | 0–4: bounce intensity |
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
| `r_rayTracingDebug` | 0 | 0 scene; 1 AO; 2 contacts; 3 bounce lighting only; 4 diffuse albedo |

For a stronger comparison, use `r_rayTracedGIStrength 3` and `r_rayTracedGISamples 8`, then toggle F6 while stationary. F10's bounce view isolates the added light; AO/contact views show occluded areas dark. The associated feature must be enabled. Console cvar changes can be followed by `neuralHistoryReset`.

## Implementation and limits

`RayTracingDiagnostic.cpp::RayTracedLighting` builds a static opaque BSP ray scene with per-vertex UVs and material indices. A GPU-only array caches 256×256 texture tiles for the first supported diffuse and additive emissive stage per material. Diffuse sampling uses the native YCoCg and sRGB-to-linear conversions. Material colors, conditions and UV transforms are evaluated each frame with the static world shader parameters.

Every output pixel traces its own primary receiver and cosine-weighted diffuse bounce rays. At visible ray hits, a pre-GI HDR snapshot supplies the renderer's complete material radiance, including native probe lighting and normal maps. Reprojection requires depth agreement. Offscreen/occluded hits evaluate textured diffuse/emissive materials and up to 16 current-view point/projected light stages with their actual projection/falloff textures, colors, texture transforms and shadow visibility rays. A short edge fade blends the visible cache with explicit lighting. The snapshot precedes GI, preventing recursive feedback. This is a hybrid single-bounce estimate; the view-dependent cache and limited light list can change as the camera turns.

`RayTracedContacts` snapshots HDR before each eligible light and attenuates only that light's opaque contribution afterward. It respects shadow-caster material flags, skips parallel lights, and retains raster shadows. A full-resolution R8 visibility image supports comparison. Copying HDR requires invalidating both the engine graphics cache and NVRHI's cached framebuffer binding; native DX12 validation caught and verified the fix for this requirement.

All rays currently intersect static opaque BSP geometry. Moving entities, the weapon, cutouts, glass, custom programs, video/GUI emission and blended vertex-color materials are not fully represented. Raster-depth agreement rejects unsupported primary receivers. Geometry normals are used for explicit offscreen lighting; the visible radiance cache includes native normal-map shading. No rough-specular ray reflections, dynamic acceleration structures or full path tracer are included. Four fixed rays can produce directional sampling artifacts; sample count is adjustable. Visual motion review remains a user playtest item.

Bounce, radiance snapshot and HDR composition use linear `RGBA16_FLOAT`. Rays and bounce output run at the full viewport resolution, including 5120×1440; there is no half-resolution mode. A 3×3 depth-aware filter operates at full resolution and excludes rejected primary receivers. Existing TAA/DLAA follows the pass, then HDR tone mapping and HUD. Texture-cache resolution is independent of render resolution. Feature-off and RT-compiled-out paths allocate no new ray resources.

`R_ClearRayTracedAO` also releases contacts, material lighting and debug caches on level changes and shutdown. Resize rebuilds bindings and viewport textures. Unsupported APIs/devices, MSAA, subviews and irradiance captures skip these optional passes; initialization failure retains raster rendering for the map.

## Short playtest

1. Launch RTX, select Native or DLAA, and load a save near colored lighting or a lit wall/corner. Install the example bindings once.
2. Toggle F6 while stationary; check reflected color and illumination in nearby shaded areas. Use F10 to isolate bounce light. Try intensity 3 if desired.
3. Walk past a doorway, rotate, fire, and resize or use 5120×1440 borderless. Check for trails, light leaks and stable HUD/FOV. F11 provides immediate rollback.

Diagnostics: `rayTracingGIStatus`, `rayTracingContactStatus`, `rayTracingAOStatus`, `hdrStatus`. GPU coverage counters prove actual work, not subjective visual quality or hardware-independent performance. Build/runtime evidence is in `TEST_RESULTS.md`.
