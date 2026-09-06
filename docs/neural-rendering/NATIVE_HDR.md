# Native HDR presentation prototype

Update 2026-09-06: after the user enabled Windows HDR, the final DLAA/RTAO run
verified active native scRGB output at 4800x1350 and after resize to 2560x720,
with finite, nonnegative presentation below the configured highlight ceiling.
See the first gameplay AO entry in `TEST_RESULTS.md`. Physical monitor
calibration and preferred brightness still need the user's visual check.

Implemented on `codex/native-hdr`, based on the `9174f4ca` modernization checkpoint. HDR is optional and defaults OFF. The source repository is now the neuralDoom task checkout; the existing game installation remains a separate build/test checkout with matching source. No runtime, game data or SDK payload is part of this change.

## Controls and behavior

Settings > System > System Options exposes HDR Output, HDR Scene White, HDR Peak and HDR UI White. Switching output requests a full game restart through the existing menu prompt; the three brightness controls apply live and are archived when leaving the menu. They describe requested settings; `hdrStatus` reports actual transport, Windows HDR state, content state and fallback reason.

| Cvar | Default | Meaning |
|---|---|---|
| `r_hdrOutput` | 0 | 0 keeps the existing SDR transport; 1 requests native scRGB, with automatic SDR fallback. Full game restart required. |
| `r_hdrPaperWhiteNits` | 200 | Scene reference white; 80-400 nits, 10-nit menu steps. |
| `r_hdrPeakNits` | 1000 | Scene highlight ceiling; 400-4000 nits, 50-nit menu steps. |
| `r_hdrUIWhiteNits` | 200 | Nominal HUD/menu white independent of scene exposure; 80-400 nits. |
| `r_hdrDiagnostic` | 0 | Non-archived shader diagnostic: exercise the HDR tone curve while preserving the current Windows display state. On SDR the presentation remains clipped to normalized white. Requires scRGB transport. |

`vid_restart` handles window/resolution changes; it is not a substitute for restarting the game after switching SDR/scRGB transport. Existing HUD layout/size still recalculate from the viewport each frame and remain archived.

## Rendering contract

- DX12 requests `RGBA16_FLOAT` / `DXGI_FORMAT_R16G16B16A16_FLOAT` and negotiates `DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709` using the swapchain's support flag and `SetColorSpace1`. Initial creation/color-space failure retries SDR. Resize reapplies the color space and can fall back to an 8-bit swapchain if reapplication fails.
- Output discovery uses the monitor containing the window and fresh DXGI output metadata at startup and resize, plus every 120 frames while scRGB transport is selected. The default SDR path does not poll DXGI each frame. `GetDesc1` reports current desktop HDR state, bits per color and reported peak luminance. Reported peak is diagnostic information, not automatic calibration. No Windows HDR setting is changed.
- On a Windows HDR display, the existing linear HDR scene/TAA/DLAA result feeds the HDR tone curve before the SDR LUT or SDR clipping. The ACES-style shoulder scales with reference white and peak luminance. The SDR path retains its existing shader branch.
- `_currentRenderLDR` and its HUD-free diagnostic copy use FP16 when scRGB transport is selected. For this prototype they contain extended gamma-2.2-encoded values normalized to UI white, retaining legacy HUD blending conventions. They are not scene-linear textures. The final swapchain blit decodes gamma, converts nits to scRGB units and bounds presentation to the configured ceiling. Intermediate blits do not apply this conversion.
- scRGB presentation uses linear BT.709 primaries. On Windows HDR, 1.0 represents 80 nits. On SDR, final output is bounded to 0-1. HDR UI reference white does not alter scene exposure.
- SDR filmic/CAS processing and its 8-bit scratch target are bypassed during HDR tone mapping. Selected retro/CRT modes and SMAA retain their SDR behavior. The temporary embedded ReShade/NR bridge keeps the 8-bit SDR transport; native Streamline DLAA remains eligible for HDR. Vulkan continues to use its existing SDR path.

This deliberately retains gamma-space HUD blending; physically linear overlay composition, HDR-aware versions of legacy post effects, gamut expansion, and perceptual tuning are follow-up work. The ordinary PNG screenshot is an SDR-clipped preview and cannot establish the appearance of HDR on a monitor.

## Automated evidence

The smoke runner can select output, require active HDR or SDR fallback, request the diagnostic, and resize during gameplay. HDR screenshots read back both the FP16 composition and the specific rendered scRGB backbuffer. Logs include dimensions, maximum channel value, values above one, nonfinite values and negative values. The runner requires finite composition, nonnegative finite presentation, HDR diagnostic highlights above one, correct PNG dimensions and a resize history reset. On an SDR desktop it also verifies the final scRGB output stays at or below one.

```powershell
.\tools\neural-rendering\Test-NeuralDoom-Smoke.ps1 -DisplayOutput SDR -ExpectedHDR SDR -Width 2560 -Height 720 -ResizeWidth 1280 -ResizeHeight 720
.\tools\neural-rendering\Test-NeuralDoom-Smoke.ps1 -DisplayOutput AutoHDR -ExpectedHDR SDR
.\tools\neural-rendering\Test-NeuralDoom-Smoke.ps1 -DisplayOutput AutoHDR -HDRDiagnostic -Width 1680 -Height 720 -ResizeWidth 2560 -ResizeHeight 720
.\tools\neural-rendering\Test-NeuralDoom-Smoke.ps1 -BuildDirectory build-streamline -Profile DLAA -DisplayOutput AutoHDR -HDRDiagnostic
```

Use `-ExpectedHDR Active` for the eventual HDR-enabled desktop test. Diagnostic success is not evidence that Windows HDR is active. Tests are serialized because the engine permits one instance; the runner reports an existing instance before launching. Detailed runs and limitations are recorded in TEST_RESULTS.md.

## Primary references

The format/color-space and luminance conventions follow Microsoft's [Advanced Color guidance](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/high-dynamic-range), [CheckColorSpaceSupport contract](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_4/nf-dxgi1_4-idxgiswapchain3-checkcolorspacesupport), and [IDXGIOutput6::GetDesc1 contract](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_6/nf-dxgi1_6-idxgioutput6-getdesc1). These are existing Windows SDK APIs; no new dependency was added.
