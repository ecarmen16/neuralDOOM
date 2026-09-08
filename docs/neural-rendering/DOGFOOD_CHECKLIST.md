# neuralDoom playtest checklist

Use this checklist for a short, repeatable graphics and settings test. Record
manual observations separately from automated build and runtime results.

## Start the build

For the internal test package, use the **neuralDoom Internal Test** Start
menu entry or the installed `Play-InternalTest.cmd`. Installation and the exact
comparison keys are documented in [INTERNAL_TESTING.md](../../INTERNAL_TESTING.md).

Setup offers Native RTX, DLAA / DLSS, and NR + DLAA profiles and downloads the
selected components. F6 compares NR with its native-resolution DLAA input.
DLSS Quality, Balanced and Performance are available in the DLAA / DLSS profile.
The shortcut opens a profile picker, then Play enters the Doom 3 menu directly.

## Five-minute check

- [ ] **Settings:** Open System Options and scroll through the graphics controls
  with both mouse and keyboard. Adjust reflection and bounce strengths separately.
  Confirm Rendering Status matches the selected profile and resolution.
  In SDR, compare Filmic Intensity at 0%, 50% and 100%; native HDR bypasses it.
  Toggle FPS Counter and resize; the compact counter should stay top-right.
- [ ] **Material lighting:** Near a screen, reflective surface or dark corner,
  compare F3 reflections, F4 bounce, F7 ambient occlusion and F8 contact shadows.
  F11 toggles all four effects together. Check that shadows remain readable and
  screen reflections do not overwhelm the original lighting.
- [ ] **Moving geometry:** Watch a door and an animated character near a reflective
  surface. Compare Moving Ray Geometry (F2) and Animated Ray Geometry in settings.
  Look for stale silhouettes, trails, missing materials or distracting noise.
- [ ] **HUD and field of view:** Select a suitable HUD layout, size and FOV. Resize
  the window and switch to the display's fullscreen resolution. Check centered
  crosshairs, readable health/ammo, PDA layout and text clipping. The FOV control
  uses a 16:9 reference value; lower it if wide-screen edge stretching is excessive.
- [ ] **Motion and effects:** Walk through a doorway, turn quickly, fire and open
  the PDA. Check for lighting pops, trails, stutter or missing effects.
- [ ] **HDR, when supported:** Enable Windows HDR before testing native HDR output.
  Calibrate Scene White, Peak and UI White for the display. Compare lamps, dark
  corners and menus. `hdrStatus` reports active output; an SDR screenshot cannot
  establish the appearance of an HDR display.
- [ ] **Persistence:** Quit normally and relaunch. Confirm graphics, resolution,
  HUD and bindings persist. Doom Lighting Defaults should restore conservative
  contrast without resetting unrelated display calibration or controls.
  Check that the launcher preselects the saved profile and DLSS quality.
- [ ] **Reconstruction transitions:** In the DLAA / DLSS profile, switch between
  DLAA, each DLSS preset in DLAA / DLSS Quality, and AA off. The image should always fill the window.
  Restore DLAA and turn or walk; check for trails after changing settings.
- [ ] **Save/load:** In a safe test session, check F5 quicksave and F9 quickload.

Optional DLAA testing should repeat the same route and settings, comparing thin
edges, grates, reflections and weapon motion. Full path tracing is not implemented;
current dynamic ray coverage is limited to supported visible opaque geometry.
Glass, particles, off-screen dynamic objects and the weapon are excluded from
that ray scene.

## Report a result

Include the build/version, profile, GPU/driver, resolution, HDR state, map, steps,
observed problem and whether a specific effect toggle removes it. Test settings
and saves are stored under `captures/dogfood`; profile logs are under
`captures/dogfood/base`. Preserve relevant logs before relaunching that profile.
Review logs and screenshots for personal information before sharing them.
