# Architecture notes

## 1. Intended layering

```text
Game/frontend scene submission
        |
        v
Existing RBDOOM renderer + NVRHI passes
        |
        +--> world/opaque/lighting/transparency
        |
        +--> HUD-free scene color candidates
        +--> depth
        +--> motion vectors
        +--> reactive/transparency masks
        +--> exposure, jitter, dimensions, reset state
        |
        v
Engine-owned temporal/neural interface
        |
        +--> Null/debug backend
        +--> Official Streamline/DLSS backend (optional)
        +--> Future official DLSS 5 backend (optional)
        |
        v
Remaining post-processing / weapon policy / UI composition
        |
        v
Tonemap/HDR output and present, according to measured pass ordering
```

The exact placement of tonemapping, bloom, viewmodel, and UI must be decided from source and GPU captures. Preserve access to multiple scene-color stages until the official API specifies the appropriate input space.

## 2. Candidate frame contract

This is a design sketch, not drop-in code. Use actual RBDOOM/NVRHI naming, ownership, math types, and lifecycle patterns after reconnaissance.

```cpp
struct NeuralFrameInputs {
    nvrhi::TextureHandle sceneColor;
    nvrhi::TextureHandle depth;
    nvrhi::TextureHandle motionVectors;
    nvrhi::TextureHandle reactiveMask;
    nvrhi::TextureHandle transparencyMask;
    nvrhi::TextureHandle hudlessColor;

    idRenderMatrix currentViewProjection;
    idRenderMatrix previousViewProjection;

    idVec2 jitter;
    float exposure;

    int renderWidth;
    int renderHeight;
    int outputWidth;
    int outputHeight;

    bool resetHistory;
};

class idNeuralRenderer {
public:
    virtual ~idNeuralRenderer() = default;
    virtual bool Initialize() = 0;
    virtual void Resize(int renderWidth, int renderHeight,
                        int outputWidth, int outputHeight) = 0;
    virtual bool Evaluate(const NeuralFrameInputs& inputs,
                          nvrhi::TextureHandle output) = 0;
    virtual void ResetHistory() = 0;
    virtual void Shutdown() = 0;
};
```

Possible implementations:

```text
NeuralRenderer_None
NeuralRenderer_DebugCopy
NeuralRenderer_StreamlineDLSS
NeuralRenderer_DLSS5Official   # only after a public SDK exists
```

## 3. Resource inventory template

Codex should fill this from the actual source before implementation.

| Resource | Producer/pass | Format | Resolution | Color/depth space | Lifetime | Consumer | Known hazards |
|---|---|---|---|---|---|---|---|
| Scene color before UI | TBD | TBD | TBD | linear HDR or display-referred | TBD | temporal backend | post-order uncertainty |
| Depth | TBD | TBD | TBD | normal/reversed Z; range TBD | TBD | temporal backend | viewmodel/transparent handling |
| Motion vectors | new or existing | likely two-channel float | render resolution | pixels or normalized TBD | frame/history | temporal backend | sign and jitter convention |
| Reactive mask | new | TBD | render resolution | 0..1 | frame | temporal backend | particle/material classification |
| Transparency mask | new | TBD | render resolution | 0..1 | frame | temporal backend | blending order |
| Exposure | existing/new | scalar/buffer | frame | pre-exposure convention TBD | frame | temporal backend | HDR behavior |
| Output | backend | TBD | output resolution | stage-dependent | frame | later post/UI | state transitions |

## 4. Motion-vector math checklist

Do not finalize formulas until matrix and API conventions are confirmed. The conceptual calculation is:

```text
current_clip  = CurrentViewProjection  * CurrentModel  * position
previous_clip = PreviousViewProjection * PreviousModel * previous_position

current_ndc  = current_clip.xy  / current_clip.w
previous_ndc = previous_clip.xy / previous_clip.w
velocity     = convention(previous_ndc, current_ndc, jitter, dimensions)
```

Questions that require measured answers:

- Does the consumer expect current-to-previous or previous-to-current velocity?
- Are vectors in pixels, normalized UV, or NDC units?
- Is Y positive up or down?
- Are current/previous jitter offsets included in matrices, removed explicitly, or passed separately?
- Is depth reversed Z? Is it device depth or linear depth?
- How are off-screen, behind-camera, newly spawned, and disoccluded pixels encoded?
- Is velocity at input/render resolution or output resolution?
- How are dynamic-resolution changes represented?

## 5. Object-history ownership

### Static world

Camera history is sufficient only for truly static geometry.

### Rigid objects

Persist previous model transforms at a stable object/surface identity. Spawn/despawn and teleport events must invalidate history.

### MD5/skinned objects

Camera-only vectors are wrong. Candidate approaches:

- previous and current joint palettes in the velocity-capable vertex shader;
- previous skinned positions retained in a suitable buffer;
- a dedicated velocity pass reusing current and prior pose inputs.

Choose based on the existing skinning path, memory cost, command structure, and shader architecture.

### Particles and procedural material animation

Many effects lack meaningful geometric previous positions. Use a reactive/history-bias policy rather than inventing false precision. Audit:

- smoke and fire;
- muzzle flashes and explosions;
- projectile sprites/trails;
- glass and alpha-blended surfaces;
- scrolling/animated material stages;
- emissive pulses and flickering lights;
- video/cinematic surfaces;
- in-world GUI surfaces.

## 6. Viewmodel and UI policy

Three viable viewmodel strategies:

1. Reconstruct world only, then render weapon and HUD afterward.
2. Reconstruct world and weapon separately, then composite.
3. Feed weapon with dedicated depth/velocity into the shared pass.

The first is the simplest but may lose desirable neural treatment on the weapon. The third is most integrated but risks projection/depth discontinuities. Make the decision from captures and tests.

HUD/menu pixels should normally be composed after temporal/neural reconstruction. In-world GUIs are scene content and need separate classification.

## 7. D3D12 and NVRHI boundary

The shared renderer should pass NVRHI handles and metadata. The optional backend may need to unwrap:

- `ID3D12Device`;
- direct command queue;
- active command list or an SDK-compatible recording point;
- `ID3D12Resource` objects for inputs/output;
- resource states and barriers;
- swapchain/output information when required.

Keep this escape hatch in one adapter. Do not spread raw D3D12 ownership assumptions through shared render code.

## 8. Failure behavior

Every backend evaluation should have an explicit fallback:

- unsupported GPU or driver;
- SDK feature unavailable;
- resource mismatch;
- resize/recreation in progress;
- evaluate call failure;
- invalid exposure or dimensions;
- missing motion-vector/mask resource;
- device removal.

A failed optional feature must return to a valid baseline path, log a useful reason once, and avoid partial-frame corruption.
