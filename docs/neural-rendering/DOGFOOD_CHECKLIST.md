# neuralDoom playtest: about 10 minutes

In the game installation's `RBDOOM-3-BFG` folder, double-click
`Launch-NeuralDoom-Dogfood.cmd`. Choose **Native** first, then quit and relaunch
with **DLAA** for comparison. The launcher verifies the exact build and opens the
main menu. Start a game, or press **~** and enter `devmap game/mars_city2` to visit
the automated test map quickly.

Both profiles share persistent test settings and saves in `captures/dogfood`.
The first launch starts in a 2560x720 SDR window. Later resolution, HUD and HDR
choices persist. This playtest uses the native renderer with the bridge disabled.

- [ ] **Ultrawide HUD:** Settings > System > System Options: choose **HUD Layout =
  Auto (16:9)** and a comfortable **HUD Size**. Resize the window and switch to
  your usual fullscreen resolution. Health/ammo should stay centered and readable;
  the crosshair should stay centered. Try Full width and Centered 21:9 too.
- [ ] **Motion and lighting:** Walk through a dark room and a doorway, turn quickly,
  fire, and watch an animated character. Check for flashes, lighting pops, trails,
  unusually crushed shadows or distracting reflections. Open the PDA and inspect
  health/ammo/objective messages for clipping.
- [ ] **DLAA comparison:** Quit, choose DLAA in the launcher and repeat the same
  route. Compare thin edges, grates, reflections and the weapon during movement.
  Note which profile looks better and whether either stutters.
- [ ] **Persistence:** Change HUD Size, leave the menu, quit and relaunch. Confirm
  the size/layout and chosen resolution remain set and still adapt to resizing.
- [ ] **Optional HDR:** Enable Windows HDR, select **HDR Output = HDR (Auto)** in
  System Options and fully restart the game through this launcher. Check bright
  lamps, dark corners and menu brightness; adjust HDR Scene White, Peak and UI
  White. `hdrStatus` should report `windowsHDR=1` and `active=1`. Ordinary PNGs
  cannot show the monitor's actual HDR appearance.

Optional RTX sanity check: in a loaded map, enter `rayTracingTest` and
`rayTracingScene`. Expect `RT_TEST status=PASS` and `RT_SCENE status=PASS`. The
second command briefly pauses to create
`captures/dogfood/base/screenshots/rt_static_world.png`, a 360-degree depth image.
This milestone proves GPU ray intersections; gameplay ray-traced lighting and
full path tracing are still upcoming. Moving props, characters and cutout
materials are outside this static-world diagnostic.

For feedback, send **Native/DLAA, map/location, what you did, and what looked
wrong**. `screenshot screenshots/dogfood.png` captures an SDR preview. Logs are
`captures/dogfood/base/dogfood-Native.log` and `dogfood-DLAA.log`; the corresponding
`build-*.json` files identify the executable used. Logs are replaced on the next
launch of that profile, so retain one if it documents a problem.
