# Legacy local launchers

The supported root launchers are `Launch-NeuralDoom.cmd` and `Launch-NeuralDoom-RTX.cmd`. They select a manifest-verified build and preserve the playtest save folder. Their new NR option also supports the existing engine-loaded compatibility stack and F6 toggle, without a DXGI proxy. Prefer that option for testing current RTX changes.

These older scripts remain available for existing local ReShade/RenoDX and D3HDP experiments. They expect a separately staged executable and runtime files at the repository root. They do not select the current build or enable the new RTX features. The ReShade switch helper is here too; all paths still resolve to the repository root.

No compatibility DLLs or mod/game assets are included. See `docs/neural-rendering/THIRD_PARTY_AND_LEGAL.md` and the existing compatibility notes before using a previously staged installation.
