# neuralDoom RTX playtest: about 5 minutes

Latest changes: [graphics controls and moving ray geometry](GRAPHICS_AND_DYNAMIC_RAYS.md).

For this build, use **option 2 (DLAA)** and check these first:

- [ ] **Settings:** Scroll to Reconstruction. Switch TAA/DLAA, adjust Reflection Strength and Bounce Strength independently, and change Ray Quality. Confirm Rendering Status stays at your full resolution. Try both mouse scrolling and the scrollbar.
- [ ] **Motion:** Watch a door open and a character move near a reflective floor or lit wall. Toggle Moving Ray Geometry, then Animated Ray Geometry. Look for stuck silhouettes, trails, missing materials or unusual noise.
- [ ] **Persistence/contrast:** Quit normally and relaunch; your reconstruction and RTX choices should remain. Doom Lighting Defaults restores conservative contrast without changing HDR calibration, ray quality or resolution.

Visual acceptance remains yours; automated checks do not judge appearance.

In the game installation's `RBDOOM-3-BFG` folder, double-click
`Launch-NeuralDoom-RTX.cmd`. Choose **DLAA** for the new controls; **Native** provides the SDK-free comparison. The launcher verifies the exact build and opens the
main menu. Start a game, or press **~** and enter `devmap game/mars_city2` to visit
the automated test map quickly.

All profiles share persistent test settings and saves in `captures/dogfood`.
The first launch starts in a 2560x720 window. Resolution and HUD choices persist.
Both launchers preserve saved HDR settings. Select HDR Output in System Options, then restart; native HDR uses Windows HDR when enabled and otherwise falls back to SDR. Native/DLAA keep the bridge disabled. Choose option 3 (NR) for the engine-loaded local compatibility stack: F6 toggles NR, F4 toggles bounce. NR uses the existing SDR compatibility output and full-resolution DLAA passthrough when disabled.

- [ ] **Material lighting:** Safe keys install automatically; remap them in Keyboard Bindings. F4 toggles full-resolution material bounce, F8 toggles contact shadows,
  and F3 toggles reflections,
  F10 cycles comparison views, and F11 toggles all RTX effects. Check colored
  lighting near a wall/corner; the new bounce default is `r_rayTracedGIStrength 1.125`.
  See [RTX_LIGHTING.md](RTX_LIGHTING.md) for controls and current limitations.
- [ ] **RTX AO comparison:** In a room with corners and nearby surfaces, enter
  `r_rayTracedAO 0`, then `r_rayTracedAO 1`. Look for changes in ambient contact
  shading. Walk, turn and watch a door/character. Report flicker, seams, excessive
  darkness or stutter. The ray scene now includes supported visible opaque moving geometry.
  Off-screen dynamic objects, glass, particles and the first-person weapon remain excluded.
- [ ] **Ultrawide HUD:** Settings > System > System Options: choose **HUD Layout =
  Auto (16:9)** and a comfortable **HUD Size**. Resize the window and switch to
  your usual fullscreen resolution. Health/ammo should stay centered and readable;
  the crosshair should stay centered. Try Full width and Centered 21:9 too.
- [ ] **Field of view:** Settings > Game Options > Field of View now spans
  **60–100** in five-degree steps. It is a 16:9 reference value: at 5120x1440,
  80 gives about 118 degrees horizontally; 70 gives about 109. Try **70** if
  objects at the edges look stretched. Back out to apply/save; no restart needed.
  Lower settings show less of the scene. Multiplayer retains its existing
  minimum of 80. Borderless mode uses the current monitor's desktop resolution.
- [ ] **Motion and lighting:** Walk through a dark room and a doorway, turn quickly,
  fire, and watch an animated character. Check for flashes, lighting pops, trails,
  unusually crushed shadows or distracting reflections. Open the PDA and inspect
  health/ammo/objective messages for clipping.
- [ ] **DLAA comparison:** Quit, choose DLAA in the launcher and repeat the same
  route. Compare thin edges, grates, reflections and the weapon during movement.
  Note which profile looks better and whether either stutters.
- [ ] **Persistence:** Change HUD Size, leave the menu, quit and relaunch. Confirm
  the size/layout and chosen resolution remain set and still adapt to resizing.
- [ ] **HDR:** With Windows HDR enabled, the RTX launcher requests HDR output on
  startup. Check bright
  lamps, dark corners and menu brightness; adjust HDR Scene White, Peak and UI
  White. `hdrStatus` should report `windowsHDR=1` and `active=1`. Ordinary PNGs
  cannot show the monitor's actual HDR appearance.

No manual diagnostics are required. `rayTracingAOStatus` is available if needed;
an enabled pass in a populated room should show nonzero `matched` and `occluded`.
AO, contact shadows, diffuse bounce and static-world reflections are implemented.
Dynamic ray geometry and full path tracing remain upcoming. The ordinary dogfood launcher
uses your saved AO setting; `r_rayTracedAO 0` returns to raster SSAO immediately.
AO replaces SSAO on matching static surfaces. Less occlusion can look brighter;
this is a change in ambient shading, not an additional light or AA technique.

For feedback, send **Native/DLAA, map/location, what you did, and what looked
wrong**. `screenshot screenshots/dogfood.png` captures an SDR preview. Logs are
`captures/dogfood/base/dogfood-Native.log` and `dogfood-DLAA.log`; the corresponding
`build-*.json` files identify the executable used. Logs are replaced on the next
launch of that profile, so retain one if it documents a problem.
