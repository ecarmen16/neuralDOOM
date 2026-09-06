# Neural Doom 3 development plan

## 1. Goal

Create a maintainable route from RBDOOM-3-BFG's existing Direct3D 12 renderer to modern temporal reconstruction and, later, publicly documented neural rendering. The work should produce useful renderer improvements even if the current unofficial DLSS 5 experiment disappears.

The central deliverable is not “a DLL hook.” It is a reliable engine-owned temporal frame contract:

- scene color without HUD contamination;
- depth with a documented convention;
- current-to-previous motion vectors for camera, rigid, and skinned geometry;
- jitter and resolution metadata;
- exposure/pre-exposure metadata;
- history-reset events;
- reactive/transparency/history-bias masks;
- deliberate viewmodel and UI ordering;
- an optional backend boundary for official vendor SDKs.

## 2. Base and target

Primary base:

```text
RobertBeckebans/RBDOOM-3-BFG
Windows x64
Direct3D 12 through NVRHI
RelWithDebInfo during development
```

Why this base:

- The DX12 renderer already exists; a ground-up OpenGL-to-DX12 port is unnecessary.
- NVRHI provides a modern resource/command abstraction and a plausible place to isolate native D3D12 access.
- The project already contains modern rendering, post-processing, HDR, AA, profiling, and debug infrastructure worth reusing.

Alternate research branch, not the initial implementation target:

```text
Inkub0/dude
Original Doom 3 data
Vulkan
Existing FSR2 Native AA, jitter, and motion-vector work
```

DUDE is valuable as a comparative reference for temporal-input design, but using two engine forks in the first implementation would fragment effort.

## 3. Scope boundaries

2026-09-06 scope extension: the user requested RTX/path-tracing investigation after the baseline, temporal, SDK and modernization work. [RAY_TRACING_PLAN.md](RAY_TRACING_PLAN.md) defines the next staged native-rendering track. The initial exclusions below remain the historical starting scope; the existing validation and dependency gates still apply.

### In scope

- Reproducible Windows build and launch workflow.
- Renderer reconnaissance and instrumentation.
- HUD-free scene output.
- Engine-native temporal data.
- Optional official Streamline/DLSS SR or DLAA integration.
- Compatibility experiments with external RenoDX/feeder tooling.
- A clean migration point for the official DLSS 5 API when public and documented.

### Out of scope for the initial project

- Rewriting the renderer from scratch.
- A full DXR/path-traced lighting renderer.
- Asset replacement, texture-generation pipelines, or remaster art production.
- Redistributing retail game data or unofficial NVIDIA runtimes.
- Supporting every renderer backend before DX12 is proven.
- Promising visual fidelity or performance before measured tests.

## 4. Work phases

### Phase 0 — Reproducible upstream baseline

Tasks:

- Clone recursively and record upstream commit.
- Create `feature/neural-rendering-spike` from a clean tree.
- Configure VS2022 x64 with:

```text
-DFFMPEG=OFF -DBINKDEC=ON -DUSE_DX12=ON -DUSE_VULKAN=OFF
```

- Build `RelWithDebInfo` without neural-renderer changes.
- Copy legally owned BFG data locally without overwriting tracked source files.
- Launch through DX12 from the repository root.
- Record GPU, driver, OS, CMake, compiler, configuration, executable hash, and launch command.

Exit criteria:

- Clean compile.
- Executable launches and reaches repeatable in-game content.
- Baseline environment and known warnings are documented.
- `git status --short` contains no retail data.

### Phase 1 — External feeder proof of concept

Purpose: answer the aesthetic/product question before committing months to engine work.

This is a **manual local experiment**, not a source dependency.

Candidate stack:

```text
RBDOOM DX12
  -> ReShade with add-on support
  -> valid scene-depth selection
  -> optical-flow provider
  -> DLSS5-Feeder synthetic DLAA call
  -> RenoDX neural-rendering interception
  -> user-supplied runtime
```

Experiment matrix:

| Axis | Cases |
|---|---|
| Resolution | 1080p, 1440p, 4K |
| Output | SDR first; HDR only after SDR is understood |
| Camera | static, slow yaw, fast yaw, lateral strafe |
| Geometry | static world, door/lift, rigid physics object, animated monster |
| Effects | smoke, flame, muzzle flash, particles, glass, animated emissive |
| Layers | weapon bob/recoil, HUD, menus, cinematics |
| AA | existing TAA off/on, feeder DLAA, native baseline |

Capture:

- Identical save/location and camera path.
- Frame time and GPU utilization.
- Still images plus short motion clips.
- Depth-buffer selection screenshots.
- Artifact notes: ghosting, UI deformation, hallucinated materials, temporal lag, instability, art-direction drift.

Exit criteria:

- A written go/no-go on whether Neural Rendering materially improves Doom 3's presentation.
- A prioritized list of defects likely solved by engine-authored inputs versus defects inherent to the model.
- No external binary committed.

### Phase 2 — Renderer reconnaissance and diagnostics

Tasks:

- Trace frontend submission to DX12 present.
- Inventory scene-color, depth, post-process, HDR, tonemapping, UI, weapon, and temporal resources.
- Determine actual TAA/jitter/history behavior.
- Locate NVRHI-to-D3D12 native access.
- Add narrowly scoped debug cvars only after recon, for example:

```text
r_neuralDebug
r_neuralCaptureFrame
r_neuralShowDepth
r_neuralShowVelocity
r_neuralShowReactiveMask
```

Names must follow existing cvar conventions and are proposals until source recon is complete.

Exit criteria:

- Render-flow and resource-lifetime documentation references exact symbols.
- Debug changes are feature-off neutral.
- GPU captures identify pass boundaries and resource formats.

### Phase 3 — HUD-free scene output and composition ordering

Tasks:

- Produce or preserve a scene-color resource before HUD/menu composition.
- Decide whether the first-person weapon is reconstructed with the world, reconstructed separately, or composed afterward.
- Preserve both useful candidate stages when practical:
  - linear/HDR scene before display tonemapping;
  - display-referred scene without HUD.
- Add a debug copy/present mode for validating the HUD-free texture.

Exit criteria:

- UI pixels are absent from the selected neural/temporal input.
- Normal rendering is unchanged when disabled.
- Resolution changes and map loads correctly recreate resources.
- Ordering is documented with a GPU capture.

### Phase 4 — Engine-authored motion vectors and temporal metadata

Implement incrementally.

#### 4A. Camera and static world

- Store previous/current view-projection state.
- Apply and document jitter convention.
- Output motion vectors at the required resolution and format.
- Validate sign, units, coordinate origin, and behavior under rotation and translation.

#### 4B. Rigid moving geometry

- Preserve previous/current model transforms for doors, lifts, projectiles, and physics objects.
- Handle newly spawned and destroyed objects without stale history.

#### 4C. MD5 skinned geometry

- Preserve previous-frame joint palettes or another correct previous-position representation.
- Generate velocity from current and previous skinned positions.
- Validate animated monsters independently from camera movement.

#### 4D. Viewmodel

- Decide separate layer versus dedicated velocity/depth treatment.
- Validate weapon bob, recoil, FOV/projection differences, and muzzle flash.

#### 4E. Unstable and transparent content

- Inventory particles, smoke, flames, glass, animated material stages, emissives, GUIs-in-world, and flashlight discontinuities.
- Generate reactive/transparency/history-bias masks or exclude problematic layers.

#### 4F. History lifecycle

Reset history for:

- map loads and save loads;
- teleports;
- cinematic or scripted camera cuts;
- resolution/output-mode changes;
- major FOV/projection changes;
- renderer restart/device recreation;
- any detected discontinuity proven by testing.

Exit criteria:

- Debug velocity is zero for static pixels with a static camera.
- Camera vectors and independently moving-object vectors differ correctly.
- Skinned characters do not use camera-only velocity.
- Newly revealed/disoccluded regions do not inherit obviously stale history.
- All conventions are written down in `IMPLEMENTATION_NOTES.md`.

### Phase 5 — Neutral neural/temporal interface

Introduce a small engine-owned abstraction after inputs exist. A design sketch appears in `ARCHITECTURE.md`; adapt it to actual RBDOOM conventions rather than copying it blindly.

Requirements:

- Inputs are NVRHI resources and plain metadata at the shared boundary.
- D3D12 native handles are unwrapped only in the backend adapter.
- Backend can be compiled out completely.
- Resize, reset, device-loss, and shutdown behavior is explicit.
- The no-backend implementation is trivial and reliable.

Exit criteria:

- Default build has no vendor SDK requirement.
- A null/debug backend consumes the same contract.
- Frame inputs are unit- and lifetime-documented.

### Phase 6 — Official Streamline/DLSS SR or DLAA integration

Before implementation, verify current official documentation, SDK version, supported hardware, API contract, and license. Do not assume the research-date version is still current.

Tasks:

- Add an OFF-by-default CMake option.
- Integrate the official SDK using a reproducible, license-compliant acquisition mechanism.
- Tag color, depth, motion vectors, exposure, and optional masks.
- Begin with DLAA/native-resolution evaluation to simplify resolution plumbing.
- Add real quality modes and dynamic render/output sizes only after DLAA is stable.
- Instrument evaluation cost and failure status.
- Handle SDK feature availability without crashing or corrupting output.

Exit criteria:

- Native DLAA works without RenoDX or feeder components.
- HUD and menus remain crisp and correctly ordered.
- Motion-vector debug scenarios pass.
- Feature unavailable/disabled returns cleanly to baseline rendering.
- Build remains functional with SDK option OFF.

### Phase 7 — RenoDX compatibility validation

Purpose: determine whether a genuine engine NGX/Streamline evaluation offers a cleaner interception point for current community experiments.

Tasks:

- Test only with user-supplied local components.
- Compare native engine temporal inputs against generic optical flow.
- Document required versions, hook order, settings, and known failures.
- Keep compatibility fixes isolated and standards-correct; do not contort the renderer solely for one unofficial runtime.

Exit criteria:

- Clear A/B evidence of input-quality improvement.
- No proprietary component in source control or release artifacts.
- Native DLSS/DLAA remains useful independently.

### Phase 8 — Official DLSS 5 migration

Begin only when NVIDIA publishes the applicable SDK/API and terms.

Tasks:

- Diff the public contract against the neutral frame inputs.
- Add newly required resources such as normals, material information, albedo, or other attributes only when documented.
- Remove unofficial compatibility assumptions.
- Revalidate visual intent, performance, supported GPUs, capture tooling, and distribution.

Exit criteria:

- Official API only.
- Reproducible legal dependency path.
- Full test matrix and release documentation.

## 5. Milestones

| Milestone | Concrete output |
|---|---|
| M0 | Unmodified DX12 build launches. |
| M1 | Feeder experiment report with go/no-go. |
| M2 | Exact renderer reconnaissance and resource inventory. |
| M3 | HUD-free scene debug output. |
| M4 | Correct static/camera and rigid motion vectors. |
| M5 | Correct MD5/viewmodel velocity plus reactive handling. |
| M6 | Neutral temporal-input interface and null backend. |
| M7 | Official native DLAA integration. |
| M8 | RenoDX compatibility report using real engine inputs. |
| M9 | Official DLSS 5 backend, when publicly available. |

## 6. Development discipline

- One focused renderer concern per branch/commit.
- Every phase begins with a written acceptance test.
- Every resource has a documented owner, lifetime, format, resolution, color space, and coordinate convention.
- Every temporal change includes a debug visualization.
- Every SDK integration remains optional.
- Generated build trees, captures, game data, and local runtimes stay untracked.
- Use RenderDoc/Nsight captures as evidence, not intuition alone.
- Performance claims require repeatable frame-time measurements and configuration details.
