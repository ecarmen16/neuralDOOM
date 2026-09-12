# Renderer architecture

neuralDOOM extends RBDOOM-3-BFG's DX12 renderer through NVRHI. Ray-traced lighting augments rasterized materials; this is a hybrid renderer, not a full path tracer.

## Rendering and reconstruction

The renderer captures scene color, depth, motion and temporal state for the optional reconstruction backend. Native rendering remains available without Streamline. DLAA uses native input resolution; DLSS presets reduce input dimensions while output and HUD retain display resolution.

D3D12 and vendor-specific calls stay in their adapters. The optional NR profile loads the compatibility components through the engine and uses SDR output. It is separate from the Streamline reconstruction backend and is not an official native NR API integration.

## Temporal resources

| Resource | Producer/pass | Format | Resolution | Color/depth space | Lifetime | Consumer | Known hazards |
|---|---|---|---|---|---|---|---|
| Scene color before UI | `_currentRenderHDR` | `RGBA16_FLOAT` | native render size, sample count explicit | linear HDR before tone map/UI | frame | temporal backend | resolve required by consumers that reject MSAA |
| Depth | `_currentDepth` | `D24_UNORM_S8_UINT` | native render size | device 0..1, non-reversed | frame | temporal backend | viewmodel uses engine depth hack |
| Motion vectors | `_taaMotionVectors` | `RG16_FLOAT` | native render size | current-to-previous displacement in pixels; +Y down | frame/history | temporal backend | invalid history clears to zero |
| Reactive mask | `_neuralReactiveMask` | `R8_UNORM` | native render size | 0..1 unstable coverage | frame | temporal backend | broad material classifier |
| Transparency mask | `_neuralTransparencyMask` | `R8_UNORM` | native render size | 0..1 alpha/glass coverage | frame | temporal backend | excludes additive-only work |
| Exposure | `TonemapPass::exposureBuffer` plus scalar | typed `R32_UINT` buffer containing float bits | one value/frame | manual scale is `exp2(r_exposure)`; buffer carries adapted luminance | persistent GPU buffer | temporal backend | current evaluation sees most recently completed adaptation |
| Output | `_taaResolved` | `RGBA16_FLOAT` | current native output size | linear HDR before tone map/UI | frame | later tone map/post/UI | backend `false` return preserves TAA fallback |

Motion vectors use current-to-previous pixel displacement with positive Y down. The queued view owns the frame identity used for jitter, motion inputs and DLSS submission. History resets on mode changes, viewport changes and scene discontinuities.

The Streamline adapter defaults DLAA, Quality, Balanced and Performance to preset K. `r_neuralDLSSPerformancePreset 1` selects M for comparison and resets history. Upscaled DLSS uses a stable reflection frame seed; `r_rayTracingReflectionStableNoise 0` restores animated sampling. Native and DLAA retain animated reflection sampling.

## Ray-traced lighting

Reflections, diffuse bounce, ambient occlusion and contact shadows have independent controls. Reflection hits replace matching probe specular; misses retain probe lighting. Moving opaque geometry and player body shadows have separate inclusion controls. See [dynamic ray geometry](GRAPHICS_AND_DYNAMIC_RAYS.md) and [reflection resources](RAY_TRACED_REFLECTIONS.md).

Stable reflection samples reduce temporal noise but can retain spatial grain or patterns in motion. Dynamic secondary-hit reprojection is not implemented. See [known issues](../KNOWN_ISSUES.md) for current limitations.

## Optional-feature failures

Unavailable SDKs, unsupported hardware and rejected evaluations must retain a working native path. Resource ownership and synchronization remain with the existing renderer and NVRHI. Runtime components and game assets are acquired separately under the policies in [dependency provenance](THIRD_PARTY_AND_LEGAL.md).
