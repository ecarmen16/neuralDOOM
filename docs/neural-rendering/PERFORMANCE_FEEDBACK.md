# Short performance feedback checklist

Use the current internal release. NR + DLSS is planned and is **not available yet**.
Keep feedback local until reviewed; no tester names or personal paths are needed.

1. Record build/version, GPU/driver, resolution, refresh rate, HDR state, frame cap
   and enabled RTX effects. Enable **System Options > FPS Counter** if needed.
2. Pick one slow location and a short repeatable route. Wait about 10 seconds for
   loading/history to settle. Keep the camera, lighting and display settings fixed.
3. In the **NR + DLAA** profile, compare F6 effect off and on. Observe each for
   about 30 seconds, repeat once, and record approximate FPS ranges and stutter.
   Label the observed NR state: the engine cannot currently report the add-on's
   toggle state reliably. These readings are observations, not formal benchmarks.
4. Relaunch into **DLAA / DLSS** and compare DLAA with DLSS Quality along the same
   route. Keep SDR for comparison with NR. Note thin edges, moving doors, weapon
   trails and any lighting/brightness differences. Balanced/Performance are optional.
5. At the slowest point, optionally compare one lighting effect at a time: F3
   reflections, F4 bounce, F7 AO, F8 contacts. Restore each before the next test.
   Report which toggle helps and whether the visual loss is acceptable.

Copy this template for each useful observation:

```text
Build/version:
GPU / driver:
Output resolution / refresh rate:
Profile / reconstruction / actual Rendering Status dimensions:
NR effect: on / off / uncertain
HDR / VSync / frame cap:
Enabled RTX effects and any adjusted strengths:
Map/location and repeatable action:
Approximate FPS range before -> after:
Stutter, ghosting, brightness or missing-surface change:
Exact toggle/setting that changed the result:
Reproduced on a second pass: yes / no
```

For a crash, include the newest session log after reviewing it for personal paths.
A short clip of the same route is useful for motion artifacts. Prioritize slow
scenes, repeatable failures and unacceptable image changes; no exhaustive matrix
or config-file editing is required.
