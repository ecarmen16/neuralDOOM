# Full-resolution material reflections — 2026-09-06

The new pass traces rough reflections through static opaque world geometry. It uses the native material's normal map, reflectivity and roughness, including both legacy specular maps and PBR materials. Matching ray hits replace the corresponding native probe specular layer. Misses retain probe lighting. This avoids stacking a second specular layer onto the existing one.

Diffuse bounce strength now defaults to **1.125**, previously 1.5: a 25% reduction. The existing local playtest configuration used 1.5 and was updated with a backup. Other installations with saved settings can enter `r_rayTracedGIStrength 1.125`; custom saved values are not automatically migrated by the engine.

## Controls

`Launch-NeuralDoom-RTX.cmd` enables reflections along with bounce, AO and contact shadows. `Launch-NeuralDoom.cmd` retains saved choices. Both support Native, optional DLAA, or the existing local NR compatibility profile. No bridge is needed. Factory defaults remain opt-in.

Safe defaults install automatically. Use Keyboard Bindings to remap actions, or Install Free RTX Keys in System Options to fill empty keys. **F3** toggles reflections, **F4** toggles diffuse bounce, **F10** cycles all seven comparison views and **F11** toggles all four effects. Custom bindings are preserved. F5/F9/F12 remain quicksave/quickload/screenshot.

| Console command | Default | Purpose |
|---|---:|---|
| `r_rayTracedReflections` | 0 | Enable/disable reflections |
| `r_rayTracedReflectionStrength` | 1 | Blend 0–1 from native probe specular toward traced hits |
| `r_rayTracedReflectionSamples` | 4 | 1–16 rays per eligible pixel; render resolution is unchanged |
| `r_rayTracedReflectionRoughness` | 0.7 | Upper roughness limit, fading to probes over the final 0.15 |
| `r_rayTracedReflectionDistance` | 2048 | Ray reach in Doom world units, range 16–8192 |
| `r_rayTracingDebug 5` | — | Reflection contribution only |
| `r_rayTracingDebug 6` | — | Accepted reflection receiver roughness; black means excluded |
| `r_rayTracingDebug 0` | — | Return to the normal scene |
| `rayTracingReflectionStatus` | — | Frame count, full-resolution dimensions and sampled coverage |

All reflection cvar changes participate in the existing temporal-history reset mechanism.

## Three-check playtest

1. **Material response:** At your usual 5120×1440 resolution, stand near glossy metal panels or a polished floor. Toggle F3, then compare views 5 and 6. Metal should reflect nearby lit geometry; matte walls should retain mostly probe lighting. Check the reduced bounce with F4 separately.
2. **Motion:** Walk sideways and turn near the reflective surface. Watch for shimmer, trails, disappearing reflections, bright speckles or hard screen-edge changes. Fire and watch a door/character; those objects are not yet in the ray scene.
3. **Transitions:** Toggle F11 off/on, resize, then reload a save or change maps. Repeat briefly in DLAA if Native looks good. Reflections should recover and the ultrawide HUD should remain stable.

The code and compiled shader contracts are checked without launching the game. This pass's GPU correctness, visual quality and 5090 performance are still playtest items. Report profile, map/location and the visible issue; no manual diagnostic run is required.

## Implementation contract

- `RenderBackend.cpp::DrawViewInternal` wraps the native ambient pass in an optional four-target framebuffer. Both `ambient_lighting_IBL.ps.hlsl` and `ambient_lightgrid_IBL.ps.hlsl` retain their original target-0 expression and emit the matching specular layer, split-sum BRDF response/roughness and normal-mapped world normal to three additional `RGBA16_FLOAT` targets. Baseline permutations retain only target 0. The capture targets overwrite together, so multi-stage materials replace only the captured layer. `PipelineCache::GetOrCreatePipeline` retains the native blend state on target 0.
- `RayTracingDiagnostic.cpp::RayTracedLighting` shares the existing static BSP AS, float3 positions, uint32 indices, float4 UV/material indices, 96-byte material/light records, texture atlas and frame-local authored lights with diffuse bounce. `PrepareRayTracedLighting`, `R_BeginRayTracedReflections`, `BeginReflections` and `RenderReflections` control capture, tracing, filtering and composition. Capture failure retains native shading. No new dependency or SDK component was integrated.
- `rt/ray_materials.hlsli` extracts the existing GI material/light/cache functions without changing their algorithm. Secondary hits use the pre-GI/pre-reflection linear HDR snapshot when projected raster depth agrees, otherwise textured diffuse/emissive shading from up to 16 current-view authored light stages. Reflections use the authored emissive scale of 1 rather than the separate GI emissive boost. Fully visible cache hits skip explicit light evaluation.
- `rt/reflections.cs.hlsl` traces at the full viewport resolution, including 5120×1440. A primary static-world hit must match raster depth within `max(0.5, distance * 0.001)` world units. Accepted pixels sample a GGX lobe using native roughness and normal maps, with geometric-normal origin bias. This is an approximate prefiltered-radiance/split-sum hybrid, not an unbiased path tracer. Incident peaks are bounded at 16 before the native material response is applied.
- Raw reflections and both filtered histories are `RGBA16_FLOAT`: RGB is incident radiance premultiplied by hit coverage; alpha is hit coverage including roughness fade. Both guide textures use `RGBA16_FLOAT`: octahedral world-normal XY, camera distance Z (bounded to 65000), roughness W. Capture textures use the full HDR target dimensions; compute textures use the full view dimensions. There is no half-resolution mode.
- `rt/reflection_filter.cs.hlsl` uses a normal/depth/roughness-aware 3×3 filter for rough surfaces and reprojects static receivers into the previous jittered world-to-clip matrix. D3D UVs have +Y down, clip depth is 0–1; distance tests use world units. History requires consecutive frontend frame IDs, identical viewport and history epoch, matching normal/roughness/distance, and finite values. The current neighborhood clamps historical lighting. Rejected receivers and current misses cannot inherit neighboring reflections. Map loads, camera cuts, FOV/resolution changes and RTX settings invalidate history through the existing epoch contract.
- `rt/reflection_composite.cs.hlsl` applies the **current** pixel's native BRDF response after filtering, avoiding transfer of another surface's reflectivity or an old Fresnel response. Normal composition is `HDR += strength * (filteredIncident * response - capturedProbeSpecular * coverage)`. Zero strength or zero current coverage leaves HDR unchanged. Debug modes 5/6 isolate contribution/roughness; earlier debug modes remain separate. Existing TAA/DLAA, tone mapping and HUD follow this pass.
- The 192-byte shared lighting constants remain unchanged. Reflection constants are 112 bytes: previous world-to-clip matrix (64), previous camera (16), sample/strength/roughness/distance controls (16), and history/frame/debug state (16). Raw passes use SM 6.5 ray queries under `USE_RAYTRACING`; baseline material shader variants remain SM 6.0 and RT-OFF builds remain supported.
- `Test-ReflectionShaderContract.py` validates 64 exact, order-sensitive engine permutation lookups, baseline versus four-target pixel output signatures, compute register bindings and constant-buffer sizes against compiled DXIL without creating a GPU device. Launcher/setup manifest requirements now include all ten RT shaders. The opt-in smoke harness adds reflection off/on, full-resolution counters and the two debug captures; it was not run for this addition.

## Known limits and next step

Ray intersections currently include static opaque BSP geometry. Doors, props, animated characters, the weapon, glass, cutouts and deformed geometry are not fully represented. Unsupported primary receivers keep native shading. Dynamic objects therefore do not yet appear in, or reliably block, reflections. The visible-radiance cache is view dependent, and offscreen fallback lacks full native probe/specular shading. Authored custom cubemap/SSR stages remain separate. These can cause changes as hits leave the screen or light lists change.

Four stochastic rays plus filtering may still show noise or trails. Filtering is engine-owned and adds no third-party denoiser. The three capture targets plus raw/history/guide textures require roughly 450 MiB at 5120×1440, in addition to the shared lighting resources. Full-resolution performance has not been measured for this pass.

The narrow next task is **rigid dynamic ray geometry**, starting with doors and movable props. It should add stable instance IDs, per-frame transforms, visibility/material filtering and clean map lifetimes before extending to animated characters.
