# Native ray intersection diagnostics

RT-001A on `codex/rt-foundation`, based on `5fab1f08`. The optional native DX12
prototype builds and queries acceleration structures on demand through the
vendored NVRHI API. It has no per-frame RT pass, gameplay lighting contribution,
new SDK or denoiser. The next gate is a persistent scene with stable mesh and
instance registration; this diagnostic does not complete that gate.

## Build and run

```powershell
.\tools\neural-rendering\Configure-RBDOOM-DX12.ps1 -BuildDirectory build-rt -RayTracing ON
.\tools\neural-rendering\Build-RBDOOM.ps1 -BuildDirectory build-rt -Configuration RelWithDebInfo
.\tools\neural-rendering\Test-NeuralDoom-Smoke.ps1 -BuildDirectory build-rt -RayTracingDiagnostics Scene -ValidationLayers 2 -ExpectedProbeLighting Local -GpuProfile -Width 2560 -Height 720 -ResizeWidth 1920 -ResizeHeight 1080 -Frames 64
```

`USE_RAYTRACING` defaults OFF and requires DX12 with DXIL. The configure helper
changes it only when `-RayTracing` is supplied. `RayTracingShaders` compiles one
raw `cs_6_5` shader with `-WX -O3 -Zpr`; the existing shader set stays at SM 6.0.
The runtime checks actual DX12 acceleration-structure and RayQuery support before
loading bytecode or allocating diagnostic resources. `rayTracingStatus` reports
capabilities, whether diagnostics are compiled, and `sceneImplemented=0` for the
absent gameplay ray scene.

| Console command | Behavior |
|---|---|
| `rayTracingTest` | One triangle, four instances, 12 known rays before and after a TLAS update. Checks hits/misses, nearest distance, IDs, translation, Y rotation, backfaces, masks, TMin and TMax. Prints 24-ray PASS/FAIL. Works without a loaded map. |
| `rayTracingScene` | Copies static opaque BSP geometry from all map areas, independent of the camera's draw list/PVS. Builds one BLAS and an identity TLAS. Traces a 512x256 panorama and compares 32 sampled nearest distances with CPU triangle traversal. Saves a grayscale depth PNG under `fs_savepath/base/screenshots`. |

World diagnostics intentionally omit rigid entities, MD5 characters, the weapon,
cutouts, translucent/deformed materials and portal skies. Two-sided opaque
intersection is used. Conditional material stages are not evaluated as live
occluder visibility. These limitations make it a geometry audit, not a complete
shadow or reflection scene. Misses are black; closer geometry is brighter using
logarithmic distance. Horizontal coverage is 360 degrees, with the current
camera's forward direction at the center and rear directions at the sides.

## Resource and synchronization contract

- `RayTracingDiagnostic.cpp::RayQueryDiagnostic` owns every buffer, BLAS, TLAS,
  pipeline and binding layout until its invocation ends. No frame-local vertex
  cache handle is retained. The graphics queue completes before readback and
  destruction; NVRHI automatic barriers order uploads, builds, dispatch and copy.
- Positions are world-space `RGB32_FLOAT`, stride 12; indices are copied to
  `R32_UINT`. The audit rejects nonfinite/out-of-range geometry and caps the copy
  at 2 million vertices and 6 million indices. Instances use NVRHI's row-major
  3x4 affine transform. Masks are eight bits and instance IDs are explicit.
- Shader/CPU input stride is 48 bytes: origin.xyz, TMin, direction.xyz, TMax,
  uint mask and three padding uints. Output stride is 16: uint hit, float distance,
  uint instance ID and uint primitive index. Static assertions guard the ABI.
  World directions are normalized; distance is in Doom world units, with the
  interval 0.01 to 8192. Miss distance is -1 with IDs `0xffffffff`.
- Synthetic comparison tolerance is 0.0001 world units. Independent CPU
  Moller-Trumbore traversal checks map samples within max(0.05, distance*0.0005).
  Every GPU map hit is checked for finite/range-valid distance and valid IDs.
- `RT_BUILD` reports vertices, triangles, instances, AS allocation bytes and GPU
  build milliseconds. `RT_TRACE` reports ray count and dispatch milliseconds.
  Timers exclude CPU copying/reference checks and do not predict path-tracing
  frame rate. One-shot blocking is intentional; persistent real-time ownership,
  incremental updates and frame overlap are future work.

Native DX12 validation exposed an uninitialized TLAS descriptor layout in
vendored NVRHI. `D3D12BuildRaytracingAccelerationStructureInputs` now initializes
its storage and explicitly selects contiguous instance-array layout. The CMake
helper compiles a corrected build-tree copy when RT is enabled; the pinned
submodule remains unchanged. See `THIRD_PARTY_AND_LEGAL.md` for the patch record.

## Failure and validation coverage

The smoke runner repeats synthetic tests before map load, after load and after
the world audit. `BuildDisabled` requires both commands to skip with no AS build
or dispatch. `MissingShader` shadows the diagnostic bytecode with an empty file
only in that run's isolated save tree and requires a contained failure before
GPU work, followed by normal gameplay completion. The installed shader is intact.
`-ValidationLayers 1` is the existing NVRHI default; `2` also enables native DX12
validation and requires the Windows graphics debug runtime.

Actual unsupported hardware and device loss have not been injected. The runtime
guard exists; only the local RTX 5090 has been exercised. Missing-shader recovery
is not proof of recovery from an invalid shader/driver/device failure. See
`TEST_RESULTS.md` for exact artifacts and remaining visual checks, and
`TEST_PLAN.md` for manual validation.
