# Native ray tracing and path tracing

Current addition: [RAY_TRACED_AO.md](RAY_TRACED_AO.md) implements opt-in static-world
ambient occlusion with a persistent AS, reusing the validated intersection path.
This supplies an early gameplay effect while the full scene/material/motion
gates below remain open. `sceneImplemented=0` still describes the incomplete full
scene; `rayTracingAOStatus` reports the actual AO dispatch and shaded receivers.

Source review and capability check: 2026-09-06, starting at `5ca342cf` on `codex/probe-lighting`. The user expanded the modernization scope to investigate RTX/path tracing while AFK. This extends the initial project's scope; it does not claim a ray-traced renderer is implemented.

The next implementation branch is `codex/rt-foundation`, prepared from the validated probe-lighting checkpoint. Build one reusable ray scene, prove intersections, then introduce shadows, reflections, diffuse bounce lighting, and finally an optional full path-tracing mode. Indirect lighting is the largest anticipated change to Doom 3's atmosphere; a single light's shadow visibility is a smaller first correctness test. These are engineering priorities, not measured visual-quality gains.

## What the current engine provides

| Component | Verified state and implication |
|---|---|
| Hardware/API | New `rayTracingStatus` reports acceleration structures, ray-tracing pipelines and inline ray queries supported on the local RTX 5090, DX12, driver 610.47. `sceneImplemented=0` explicitly distinguishes capability from implementation. |
| Graphics abstraction | Vendored `neo/extern/nvrhi/include/nvrhi/nvrhi.h` exposes acceleration structures and ray queries. `RayTracingDiagnostic.cpp` now uses this abstraction for on-demand known-ray tests and a static-world audit. Persistent gameplay scene construction is the next step. |
| Shader compilation | `neo/compileshaders.cmake` currently requests shader model 6.0. An inline-ray-query experiment needs its own 6.5-or-later shader target and capability gate, without raising the baseline's requirements. Microsoft's [DXR specification](https://microsoft.github.io/DirectX-Specs/d3d/Raytracing.html) defines RayQuery from shader model 6.5 and the required traversal/build behavior. |
| Geometry | `idRenderWorldLocal::localModels/entityDefs`, `Model_md5.cpp`, `VertexCache.h` and `NVRHI/BufferObject_NVRHI.cpp` expose useful scene data, but do not manage an RT scene. Current vertex/index buffers are not marked as acceleration-structure build inputs. Their lifetimes and offsets require explicit handling. |
| Lighting/materials | `RenderBackend.cpp::AmbientPass`, `DrawInteractions`, `RenderInteractions`, `neo/shaders/BRDF.inc.hlsl` and the interaction/IBL shaders define the existing appearance. Reflection hits need material evaluation outside the current screen's G-buffer. |
| Temporal/HDR | `_currentRenderHDR` is linear RGBA16F; depth, motion, normals/roughness, history epochs and separated overlay UI already exist. These are useful inputs, but require adapters and additional buffers for ray denoising. Native scRGB presentation is an independent output feature. |
| Other backends | `DeviceManager_VK.cpp` has optional RT extension handling, controlled by `DeviceCreationParameters::enableRayTracingExtensions` (currently false by default). DX12 is the first validated target; shared scene and pass code should remain in NVRHI. Vulkan capability parity is not yet tested. |

The configured Windows SDK 10.0.26100.0 DXC compiled the initial isolated `cs_6_5` probe. The subsequent RT-001A implementation now dispatches known rays and static-map panoramas on the GPU; see [RAY_TRACING_DIAGNOSTICS.md](RAY_TRACING_DIAGNOSTICS.md). It is an ephemeral diagnostic scene, not persistent gameplay RT.

## Implementation sequence and acceptance gates

| Stage | Concrete work | AFK exit evidence |
|---|---|---|
| RT-001: intersections | Add an OFF-by-default native RT option, a separate compute shader target, persistent static-mesh BLAS, an instance TLAS, build/update synchronization, and an ID/distance debug output. First prove a synthetic triangle, then a small retail-map region. Retain resource ownership until the GPU has finished. | Known hit/miss rays agree with CPU reference triangles; instance transforms and visibility masks work; static geometry behind the camera remains hittable; shader/build errors and unsupported features give a working raster fallback. Count triangles, instances, AS bytes and build time. |
| RT-002: scene motion and cutouts | Extend scene registration to doors, lifts and rigid objects, then MD5 skinned geometry. Produce posed vertices for BLAS updates using the same joint/weight convention as raster skinning. Apply alpha-test UV transforms and thresholds at ray hits. | Moving-door occlusion, translated/rotated props, animated silhouettes and perforated grates match the raster scene. Map changes release/rebuild AS resources safely. No reliance on the current camera's draw list or PVS alone. |
| RT-003: direct shadows | Replace visibility for one selected authored light while retaining its projection, attenuation, material stages and direct-light calculation. Start with deterministic hard shadows. Add finite-source soft shadows and filtering only after hard visibility is correct. | Numeric visibility-mask readback, contact/self-shadow checks, moving occluder sequence and per-pass timings. Disabling RT restores existing shadow rendering. A controlled light setup is needed before claiming physically meaningful penumbra sizes. |
| RT-004: reflections | Trace one-bounce specular rays and evaluate hit materials/lights, including objects outside the screen. Define roughness/ray-distance budgets and an explicit fallback for unsupported surfaces. | A reflected object remains present after it leaves the screen; roughness changes, doors and animated objects are coherent. Mirror/subview, glass and world-GUI cases have documented behavior. Distinct radiance/hit-distance outputs support denoising. |
| RT-005: indirect lighting | Sample diffuse bounce lighting, preserve separate diffuse/specular signals, and add a temporal/spatial filter with disocclusion rejection. Replace the corresponding baked/probe contribution where ray lighting is enabled. | A controlled emissive/light-color change affects nearby surfaces, occluded regions remain dark, moving objects do not leave persistent lighting trails, and exposure changes do not destabilize history. Probes, light grids, SSAO and ray GI are not counted twice. |
| RT-006: full path tracing | Add a primary-ray integrator, BSDF/light sampling, multiple bounces, emissive contribution, importance sampling and controlled accumulation. Integrate resolved linear radiance before existing HDR/tone mapping and overlay composition. | Small deterministic reference scenes, high-sample convergence comparisons, finite-radiance checks, moving scenes, resize/cuts and benchmark maps. Account explicitly for glass, particles, fog, decals, world GUIs and the first-person weapon before claiming complete game support. |

The RT scene must include potential shadow casters and reflected geometry that camera culling would remove. Start with conservative map geometry; optimize ray-relevant culling after correctness. BLAS updates for animated meshes are different from TLAS transform updates for rigid instances. Frame-local raster vertex handles must not become long-lived AS references accidentally.

The weapon's depth hack is a raster projection policy, not a physical world transform. Choose its ray visibility and self-shadow/reflection policy explicitly. Additive effects, muzzle flashes, animated emissives and transparent materials also need explicit sampling/composition rules. Extra rays do not create missing geometric detail or improve silhouettes by themselves.

## Denoising and the NR relationship

Native DLAA handles anti-aliasing; it is not a substitute for filtering stochastic ray lighting. The current experimental NR bridge is not the source of geometry intersections. Validate native ray lighting independently, then evaluate how the optional neural path should consume its result through a documented API.

Begin with deterministic visibility and an engine-owned reference accumulator so progress does not depend on a new SDK. For real-time noisy lighting, evaluate a maintained denoiser against an explicit buffer contract: normal/roughness, linear view depth, motion vectors, separate diffuse/specular radiance and hit distances, exposure, and reset state. Existing motion vectors are current-to-previous pixels with +Y down; a denoiser adapter must convert its expected convention rather than pass them blindly.

[NVIDIA NRD](https://github.com/NVIDIA-RTX/NRD) supplies shadow and diffuse/specular denoisers, but its current [RTX SDK license](https://raw.githubusercontent.com/NVIDIA-RTX/NRD/master/LICENSE.txt) is not the MIT license used by NVRHI. Record compatibility and distribution review before integration into this GPL project. NRD and DLSS Ray Reconstruction are candidates, not added dependencies or available features. No new SDK is required for the initial DXR scene and visibility tests.

## Performance and unattended validation

Use the existing exact-artifact build manifests, bounded smoke runner and GPU timing export. Add separate AS-build, ray-dispatch and denoise timers; retain total GPU time because passes can overlap. Begin at a modest debug resolution and fixed seeds, then cover 2560x720 and the verified 4800x1350 windowed ultrawide size. Full 5120x1440 is 7,372,800 pixels; ray count, render resolution, bounce count and denoising cost need measured quality modes. Earlier raster timings do not predict path-tracing performance.

Both SDK-OFF and the existing SDK-ON build must keep working. Exercise disabled, unsupported, missing-shader and device-loss paths, then map load, cut, resize and mode changes. Automated readbacks, captures and short motion sequences can establish correctness while the user is AFK. Preferred darkness, reflection strength, denoising softness and HDR display calibration remain eventual visual decisions.

RT-001A implements the OFF-by-default synthetic test and static-map audit. Next, RT-001B must add persistent scene registration, stable mesh/instance identity, map-lifetime cleanup and a material mapping before RT-002's moving geometry and RT-003's selected-light shadows. No full path-tracing quality preset or frame-rate target is promised at this checkpoint.
