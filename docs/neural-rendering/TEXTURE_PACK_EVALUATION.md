# Community texture-pack evaluation

This document tracks external, local-only visual-content candidates for Neural Doom 3. Texture packs, models, retail data, generated resources, bundled executables, and their archives must remain outside Git. A candidate is not approved for redistribution merely because it works locally.

## Initial shortlist — 2026-09-02

| Priority | Candidate | Fit for this project | Main risks | Initial disposition |
|---|---|---|---|---|
| 1 | [D3HDP BFG Lite](https://www.moddb.com/downloads/d3hdp-bfg-lite) | Explicitly targets Doom 3 BFG with RBDOOM-3-BFG 1.6.0 or newer; provides HD textures/models and restored details; author describes no gameplay changes and a separate `mod_D3HDP_Lite` directory. | Asset provenance and redistribution terms require archive inspection; reports mention installation confusion and at least one RoE map issue. | Best first isolated A/B candidate. |
| 2 | [Doom 3 BFG: UltimateHD 2.1.1](https://www.moddb.com/mods/doom-3-bfg-ultimate) | BFG-specific and isolated under `@UltimateHD`; can be launched with `+set fs_resourceLoadPriority 0 +set fs_game @UltimateHD`. | Old release; changes particles, sounds, AI, weapons, and gameplay in addition to textures; bundled executable must not replace the custom build. | Evaluate only after the texture-focused candidate, and treat it as a broad overhaul rather than a texture pack. |
| 3 | [Doom 3 BFG Hi Def 4.0](https://www.moddb.com/downloads/doom-3-bfg-hi-def-40-full-release) | BFG/RBDOOM-oriented, large texture and high-poly-model collection. | Ships around its own executable/config/effects stack, has reported startup and bloom issues, and is more likely to collide with this renderer branch and ReShade chain. Licensing/provenance require inspection. | Reference/asset-comparison candidate, not the first installation. |

## Evaluation criteria

1. Install each candidate into its own mod directory without overwriting `RBDoom3BFG.exe`, ReShade, Streamline, or engine configuration.
2. Inventory archive contents and locate explicit license/readme/provenance before copying assets.
3. Compare identical saved-game views with native assets and the pack, first with NR off and then with the chosen NR settings.
4. Inspect diffuse/base-color fidelity, normal-map quality, specular or RMAO behavior, seams, alpha edges, animated screens, characters, weapons, and memory/loading impact.
5. Reject packages that require replacing the custom executable or irreversibly mixing files into `base`.
6. Keep all downloaded archives, extracted assets, screenshots, and generated resource caches untracked.

## Narrow next task

Download D3HDP BFG Lite to a disposable local staging directory, inspect its archive manifest and documentation, then create a separate launch profile using `fs_game` only if it can coexist without replacing engine or runtime files.
