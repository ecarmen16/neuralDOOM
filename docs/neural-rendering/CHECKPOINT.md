# RTX material-lighting checkpoint — 2026-09-06

The user requested that no more applications/GPU tests launch while they use the RTX 5090. No game process remained when work was checkpointed. Resume GPU work only after the user indicates it is available.

## Implemented

- Full-resolution material-aware diffuse bounce, emissive contribution and colored indirect light; static opaque BSP intersections with texture UVs. Visible hits reuse native HDR material radiance; offscreen hits evaluate textured materials and up to 16 view light stages. No half-resolution rendering.
- Ray-traced contact shadows supplement each existing light's raster contribution. AO strength and sample controls are adjustable.
- Optional `exec neural_rtx_keys.cfg`: F6 GI, F7 AO, F8 contacts, F10 debug views, F11 master toggle. Debug mode 4 displays ray-scene diffuse albedo.
- Two supported root launchers: normal and RTX. Earlier NR/mod launchers and the ReShade switch wrapper moved into `tools/neural-rendering/legacy` with corrected root paths.
- Setup defaults to native rendering, checks the exact executable/manifest and seven RT shaders, detects absent RBDOOM lighting data, accepts the verified extracted lighting pack, supports a source build and a read-only readiness check. Legacy runtime prompts require opt-in.

## Last passing GPU run

`captures/neural/smoke-20260906-192933-7ef79bd1/result.json` in the game checkout: Native DX12, SDK OFF, RT ON, RelWithDebInfo, native D3D12 and NVRHI validation, 1280×720 → 1920×1080, 600 warmup frames, 64 profile samples, normal exit. Exact executable SHA-256:

`C73236FFBF12ABD80CBF04BF4E5FDD4C41EBC0A896D8E5738E522946947790DA`

The manifest records dirty source based on `66c22315`. This is a tested development artifact, not the final checkpoint binary. Before/after/feature-off and three visibility captures exist; all three ray features stopped and resumed correctly. Final GI counters: 3,001 matched sampled receivers, 10,595 bounce hits, 339 colored contributions, 1,058 modified samples, 3,447 cached-radiance hits, 18 emissive hits, zero invalid values. Keybind serialization and four-mode cycling passed. Afterward, mode 4/albedo and empty-light contact-debug reset were added without another build or GPU run.

Native setup validation, setup failure fixtures, build-identity fixtures and all PowerShell parser checks passed without launching a game. The current game checkout already contains the official 1.6.0 lighting pack; runtime checks confirm 98 complete Mars City 2 probe pairs and 93 populated grids. A separate RBDOOM executable installation is unnecessary.

## Resume here

1. Build this checkpoint in `build-rt`, `build-streamline` and the default RT-OFF `build`, using the existing helpers. Preserve local assets, SDK files and playtest settings. The updated sources have not yet been validated in the latter two configurations.
2. Run the focused native smoke with AO, contacts, GI, five debug views and resize. Inspect `material_albedo.png` and `material_bounce.png`; bounce light in the elevator view is faint, so use an open room/colored light for a useful visual comparison. Do not describe coverage counters as proof that the effect is visually dramatic.
3. Run DLAA + native HDR at 5120×1440 borderless (`-Borderless -FieldOfView 70`) with all RTX features, then a brief RT-compiled-out check. Serialize all game runs because of the global DOOM3 mutex. No saved user settings or bindings should change.
4. Check one map reload and missing-shader fallback for the new material resources. Reconfirm exact executable hashes and record final evidence. Final performance at 5120×1440 is unmeasured.
5. Run `Setup-NeuralDoom.ps1 -ValidateOnly` for both profiles and the source audit. The source installer passed local read-only checks; fresh-machine/toolchain installation and combined binary redistribution are not certified.

Do not push while GitHub login is pending. The local source can be reviewed/committed; retail data, lighting packs, captures and NVIDIA runtimes remain ignored. No GPU continuation, launch or automated follow-up has been scheduled.
