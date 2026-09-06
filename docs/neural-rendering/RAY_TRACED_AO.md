# Native ray-traced ambient occlusion prototype

`Launch-NeuralDoom-RTX.cmd` starts the verified Native or DLAA playtest with
`r_rayTracedAO 1`, SSAO enabled, the new SSAO pass selected and native HDR (Auto)
requested. Windows HDR determines HDR availability. Toggle
`r_rayTracedAO 0` / `1` in the console during play. The default is OFF; this
setting and `r_rayTracedAORadius` (default 64 Doom units, range 1–256) are archived.
No ReShade bridge or additional SDK is involved. This adds ambient contact
shading; direct-light ray shadows, reflections and full path tracing remain
separate work.

## Implementation and resource contract

- `RayTracingDiagnostic.cpp::GatherStaticWorld` shares the already validated
  all-area opaque BSP extraction with the diagnostics. `RayTracedAO` retains
  immutable float3 positions (12-byte stride), uint indices (4-byte stride), one
  BLAS and one identity TLAS instance across frames. Initialize once per map;
  `RenderSystem_init.cpp` clears ownership at `BeginLevelLoad` and `Shutdown`.
  A changed render-world pointer also clears the cache. The existing NVRHI
  command-list references retain submitted resources until GPU completion. The
  initial upload/build uses a deferred list so it can run while the renderer's
  immediate list is recording; only initialization waits for that build.
- `RenderBackend.cpp::DrawScreenSpaceAmbientOcclusion2` runs AO after SSAO and
  before ambient lighting consumes `_ao0`. Matching static receivers replace
  SSAO; omitted receivers retain SSAO. No extra multiplication of both effects.
  Subviews, irradiance baking, disabled SSAO and the legacy SSAO path skip it.
- `ambient_occlusion.cs.hlsl` is a separate raw SM 6.5 compute shader, built by
  `neo/shaders/CMakeLists.txt` only with `USE_RAYTRACING=ON`. Runtime requires
  DX12 acceleration structures and inline ray queries. Build OFF, runtime OFF,
  unsupported hardware and initialization failure retain raster rendering.
  Initialization failure is reported once per world and retried on map load.
- The 96-byte volatile constant buffer contains the row-major inverse
  view-projection matrix, world camera/radius and pixel viewport. Raster depth
  uses DX12 Z 0–1; pixel centers map to clip XY with Y up. Unprojection is
  `mul(ClipToWorld, clipPosition)`. A primary closest ray must match raster depth
  within max(0.5 world units, 0.1% distance), rejecting most omitted receivers
  including the depth-hacked weapon. Triangle normals are oriented toward the
  camera; this pass uses geometry normals rather than normal-map detail.
- Eight fixed cosine-weighted hemisphere rays use a 0.5-unit origin bias and
  distance-weighted occlusion. Full-resolution R8_UNORM `_ao0` is written via
  `RWTexture2D<float>`. There is no new temporal accumulation or denoiser.
  Existing TAA/DLAA receives the resulting scene color. Texture bindings refresh
  automatically on resize; the world AS remains reusable.
- `rayTracingAOStatus` reports dispatch frames and GPU sample/receiver/occlusion
  counters sampled on a 32-pixel grid. Only this explicit command reads back and
  waits for the GPU. Normal frames do not wait or rebuild the AS. The marker
  `Ray-traced ambient occlusion` sits within the existing SSAO timing interval.

## Scope and validation

This deliberately covers static opaque map geometry only. Doors, props,
characters, cutouts, deformed geometry, glass and sky are not ray occluders.
Raster SSAO remains for receivers missing from this scene; the depth agreement
check is an approximation, not a material/instance identity buffer. Fixed sparse
rays can create bands and triangle-normal seams. Radius/bias and frame cost need
visual judgment in representative rooms. UI rendering remains downstream.

Build with `Configure-RBDOOM-DX12.ps1 -BuildDirectory build-rt -RayTracing ON`,
then `Build-RBDOOM.ps1 -BuildDirectory build-rt -Configuration RelWithDebInfo`.
`Test-NeuralDoom-Smoke.ps1 -BuildDirectory build-rt -RayTracedAO -GpuProfile`
checks actual shaded receivers, live OFF/ON, GPU progress, captures and optional
resize. `rt_off.png` records the raster comparison. See `TEST_RESULTS.md` for
measured evidence and `DOGFOOD_CHECKLIST.md` for the short visual check.

Next: add stable mesh/instance/material registration and moving/cutout occluders
before implementing authored-light ray shadows. This prototype does not close
the full RT-001B/RT-002 scene-completeness gate.
