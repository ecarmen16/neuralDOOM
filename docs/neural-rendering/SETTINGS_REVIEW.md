# Rendering settings review — 2026-09-07

Goal: preserve Doom 3 shadow contrast while retaining full-resolution material lighting and DLAA. These are conservative starting values, not a claim of exact 2004 renderer matching. Visual comparison remains with the user.

## Findings and changes

- `TonemapPass::SimpleRender` unconditionally computed histogram exposure even with `r_hdrAutoExposure 0`. It now honors that switch, which is archived. Fixed mode uses a new `r_hdrFixedLuminance 0.5` reference: the former adaptive bright-scene ceiling, without the adaptive boost in darker rooms. `r_exposure` remains an EV multiplier, applied by the tone mapper. This correction can darken some rooms considerably more than the 25% ambient reduction.
- `TonemapPass::ComputeExposure` supplied total uptime as adaptation delta time. It now receives elapsed time, bounded to 0–0.25 seconds, and initializes the exposure buffer to a defined value. Automatic exposure is optional (`r_hdrAutoExposure 1`). Its histogram range and adaptation-rate controls remain available.
- `idStreamlineNeuralTemporalBackend::Evaluate` only refreshed DLSS options after resize/mode changes. It now refreshes exposure metadata when the Brightness setting changes. Internal DLSS auto exposure remains enabled: the official SDK guide requires it when no exposure texture is supplied. Our engine exposure buffer is an adapted-luminance buffer, not directly a compatible exposure texture. Do not tag it as one or assume internal normalization is a second display brightness pass. This fixes stale metadata; it does not prove the reported DLAA brightness difference is resolved.
- Ambient factory default is reduced 0.5 → 0.375. It scales both diffuse probe lighting and specular response, including the captured RTX response; setting it to zero would also suppress those reflections.
- Reflection blend factory default is reduced 1 → 0.65. GI remains 1.125, already 25% below the earlier 1.5 default. Lower reflection blend restores more probe contribution; it is not a uniform 35% brightness reduction.
- System Options now calls the old Blood Reflections control **Material SSR**, with an explanation. `r_useSSR` selects the SSR shader for authored `TG_REFLECT_CUBE2` stages with bump maps and Hi-Z available. This is material-scoped screen tracing, not a blood-name check or a screen-wide reflection pass. Its off mode uses the existing environment fallback.

## Defaults and control audit

| Area | Starting values / decision | Controls and limits |
|---|---|---|
| Scene contrast | Ambient 0.375; fixed luminance 0.5; exposure +0.5 EV | Ambient and Brightness menu controls; fixed/automatic exposure via console. Saved exposure remains user-owned. |
| Direct lights | Light scale 3; bump/specular/shadows enabled | Preserve authored lighting rather than reducing all direct light. Saved light scale is not overwritten. |
| HDR | Factory SDR; launcher AutoHDR option; scene white 200, peak 1000, UI white 200 nits | Existing sliders are sufficient for calibration. Actual display peak is not a GPU capability. Preserve the user's saved peak 650 and UI white 160. |
| RT diffuse | Off by factory; RTX launcher enables; strength 1.125, 4 rays, radius 384, emissive 2 | Intensity and quality are separate cvars. Leave emissive at 2 until tested separately; visible radiance cache and explicit offscreen lighting differ. |
| RT reflections | Off by factory; RTX launcher enables; blend 0.65, 4 rays, roughness limit 0.7, distance 2048 | Full viewport resolution. Static opaque world geometry only; dynamic geometry remains future work. |
| Occlusion | SSAO on; RT AO optional, strength 1, 8 rays, radius 64 | RT AO feeds the existing AO path; retain SSAO enable as required by that path. Do not disable it thinking it is a redundant independent effect. |
| Contacts | Optional, strength 1, distance 128 | Supplement raster shadows; keep raster shadows enabled. |
| SSR | On, authored reflective materials | Separate from RT reflection toggle; not all materials contain the required stage. A universal SSR pass is a new feature, not an unfinished checkbox. |
| AA / reconstruction | Native TAA or native-resolution DLAA in launcher | DLAA uses preset K. Backend 3 currently selects DLSS Quality, but a complete dynamic-resolution/quality menu is not implemented. Do not expose Balanced/Performance labels without corresponding render-size handling. |
| Temporal quality | Jitter on, object motion on, history clamping on, new-frame weight 0.1 | Keep measured conventions; avoid artistic brightness compensation inside DLAA. Match exposure/scene/profile when comparing. |
| Resolution / filtering | Launch forces 100% scene fraction; trilinear on, anisotropic 8 | No half-resolution ray pass. 16x anisotropic is an optional texture-quality preference, unrelated to lighting. LOD bias is marked unused; do not expose a nonfunctional dial. |
| Presentation | Saved VSync/frame cap; motion blur off; render mode Doom; CRT off | Preserve user latency/refresh choices. Launcher deliberately selects Doom mode and temporal-compatible AA. |
| Filmic / bloom | Filmic on; CRT off | Filmic adds grain/chromatic effects. The modern backend bloom block is TODO; legacy bloom cvars are not functional modern quality controls and should not become menu sliders. |
| Ultrawide / HUD | Existing aspect-aware HUD sizing and 16:9-reference FOV | Preserve working saved layout; no forced 5120x1440 or per-res HUD reset. FOV and HUD are separate preferences. |
| NR compatibility | Manual local profile; no upscaling; F6 addon toggle | Uses embedded ReShade/RenoDX, not a native public NR API. Transport remains SDR even with Windows HDR. NR tuning is separate and not suitable as native HDR calibration. |

## Saved settings and launch precedence

The inspected playtest config again contained GI strength 1.5 and reflection blend 1, despite the earlier offline reset. The cause is unproven; the game may have saved older in-memory values or another session may have changed them. Changing factory defaults does not replace archived settings. Do not repeatedly edit a potentially live config.

The normal launcher now applies the contrast preset automatically once, after the saved config loads, and backs up the old config. A versioned marker is written only after a successful game exit; preparation and failed sessions retry. Subsequent launches preserve later tuning. `exec neural_rtx_contrast.cfg` remains an optional manual reset. It sets fixed exposure, ambient 0.375, GI 1.125 and reflection blend 0.65, preserving HDR calibration, resolution, feature enables and sample counts. Launchers do not force these strength settings every time, so subsequent tuning remains possible. The RTX launcher does explicitly enable its four ray features. Native/DLAA/NR selection is launch-owned; NR reserves F6 and moves GI to F4.

## Focused validation

Build all three existing RelWithDebInfo configurations, inspect the diff and launcher build-identity checks. No game or visual capture is launched for this review. Resource formats and coordinate conventions are unchanged: HDR scene RGBA16_FLOAT, adapted luminance stored as float bits in the existing uint exposure buffer, DLSS exposure metadata scalar, existing motion conventions unchanged.

User checks: launch normally, compare a dark corner and a bright terminal in Native/DLAA with identical settings; adjust Brightness during DLAA and verify it responds consistently; toggle `r_hdrAutoExposure 1` then `0` and verify only automatic mode adapts; exit/relaunch and check persistence. Material SSR can be compared on blood/polished authored materials separately from `r_rayTracedReflections`.

Next bounded task: menu controls for reconstruction mode and independent RTX strengths, showing active backend and actual render/output resolution. Dynamic ray geometry is a separate rendering task.
