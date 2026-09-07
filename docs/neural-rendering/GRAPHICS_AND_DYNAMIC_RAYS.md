# Graphics controls and moving ray geometry

Settings > System > System Options now includes reconstruction, current backend/resolution, independent RTX toggles, reflection/bounce/emissive strengths, moving/skinned geometry controls, Ray Quality and Doom Lighting Defaults. Scroll below Volume.

Use the DLAA launcher profile to switch live between native-resolution TAA and DLAA. The Native build has no SDK; the NR profile keeps DLAA as its input. This adds no DLSS upscaling modes. Ray Quality selects 2/4/8/16 reflection and bounce rays, with twice as many AO rays. It never reduces rendering resolution. Defaults preserve GI 1.125, reflection blend 0.65 and the existing dark, fixed-exposure preset. The launcher seeds missing RTX preferences and respects saved on/off choices thereafter.

## Dynamic geometry implementation

`R_SnapshotDynamicRaySurface` in `neo/renderer/tr_frontend_addmodels.cpp` creates frame-owned world-space position, UV and index copies for directly visible opaque entities. Rigid transforms and current GPU skinning poses follow existing engine joint/weight conventions; CPU-skinned vertices are already posed. Frame copies prevent the backend from reading geometry mutated by a later frontend frame. Evaluated per-entity material registers retain skins, texture transforms and animated emissive values.

`rayDynamicSurface_t` and per-view entity fields are in `RenderCommon.h`. `RayQueryDiagnostic::{Initialize,UpdateDynamic}` in `RayTracingDiagnostic.cpp` retain the static BLAS and rebuild a bounded dynamic BLAS plus two-instance TLAS on the existing command list. AO, contact shadows and material lighting consume the updated scene; shadow exclusion flags are respected. Positions are RGB32_FLOAT world units, indices R32_UINT, and UV/material records RGBA32_FLOAT. Dynamic instance IDs carry the global primitive offset; `diffuse_bounce.cs.hlsl`, `reflections.cs.hlsl` and `ray_materials.hlsli` add that offset before material lookup. HDR lighting remains RGBA16_FLOAT at full viewport resolution.

The frontend caps each entity at 32,768 copied vertices. Each ray scene accepts up to 128 surfaces, 131,072 vertices and 393,216 indices. The material atlas reserves 128 dynamic diffuse/emissive pairs, adding approximately 128 MiB. No SDK/dependency changes. The feature-off build does not gather dynamic ray snapshots.

`idMenuDataSource_SystemSettings::{LoadData,AdjustField,GetField,IsDataChanged}` and System Options rows in `MenuScreen_Shell_SystemOptions.cpp` implement the controls; `MenuScreen.h` stores their original values. Absolute row selection/focus now remains correct after scrolling, including `idMenuWidget_SystemOptionsList::ScrollOffset` and `MenuWidget_Scrollbar.cpp`. `R_GetNeuralPresentationStatus` in `RenderBackend.cpp` / `NeuralTemporal.h` exposes atomic last-frame backend and extent telemetry. `RenderBackend_NVRHI.cpp::Init` retains the initialized Streamline adapter when starting with saved TAA so switching to DLAA works live.

## Current limits and rollback

- Only directly visible opaque entities are gathered. Reflections cannot yet retain off-screen moving actors; visibility changes may cause popping.
- Glass, particles, deformed materials, subviews and the first-person weapon are excluded.
- Per-effect dynamic BLAS rebuilding and skin copies add CPU/GPU work; this is not an optimized persistent per-entity cache.
- Reflection temporal accumulation is suspended while dynamic surfaces are present because secondary-hit motion is not yet tracked. Spatial filtering and TAA/DLAA remain; extra reflection noise is possible.
- `r_rayTracingDynamicGeometry 0` restores static-only tracing; `r_rayTracingSkinnedGeometry 0` excludes animated geometry. Both are archived and reset temporal history when changed. `rayTracingDynamicStatus` reports accepted surfaces/triangles, skinned surfaces and backend budget exclusions.
- `rayTracingDynamicTest` checks insertion, movement, no-shadow filtering and removal with GPU ray queries. `Test-DynamicRayGeometry.py` separately exercises actual CPU snapshot/gather source, including offsets, joint weights and invalid inputs.

Next narrow task after visual feedback: measure dynamic BLAS cost and extend visibility/secondary-hit history without sacrificing Doom contrast. See TEST_RESULTS.md for build/runtime evidence and DOGFOOD_CHECKLIST.md for the short user test.
