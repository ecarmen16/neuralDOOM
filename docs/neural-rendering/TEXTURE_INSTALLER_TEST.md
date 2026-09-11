# Local texture-installer experiment

Branch: `codex/texture-pack-installer`. This is not the published Milestone 1 installer.

Choose **New separate installation**, an empty destination, your owned BFG game and a rendering profile. The next page offers **D3HDP BFG Lite**, selected by default for this test. Setup tries the original ModDB download; if blocked, download `D3HDP_BFG_Lite.zip` from the [BFG Lite project](https://www.moddb.com/mods/d3hdp-bfg-lite/downloads/d3hdp-bfg-lite) and select it on that page. The original-Doom-3 D3HDP v2.0 pack is incompatible with this installer and is rejected.

Allow approximately 4.3 GB of downloads and 32 GB free for a fresh installation. Selecting no texture pack retains the M1 installation path. On an existing installation, unchecking the pack skips acquisition; it does not remove previously installed assets. Use separate clean installs to compare.

## Attribution and asset loading

D3HDP BFG Lite is by **H3llBaron and the contributors credited in its original readme**. Setup displays that credit and preserves the downloaded top-level readme byte-for-byte at `notices/D3HDP-BFG-Lite/Readme.txt`, along with other included credit documents. The installed manifest records the project URL, archive SHA-256 and installed file hashes. No pack assets or third-party readme contents are committed or bundled in our release payload.

This local experiment loads the content as `base/zzz_neural_d3hdp_*.pk4` overlays. Original PK4 files retain their bytes; supported loose content is assembled into a local PK4. Loose mod launchers and CFGs are preserved under notices rather than executed or applied. Save/config paths remain `captures/dogfood/base`, so existing reset and snapshot tools continue to use the same location. This differs from the author's separate `fs_game` launch method and requires visual validation. No renderer code changes are part of this branch.

## Validation and limitations

- Actual importer passes isolated ZIP fixtures: original-readme retention, deterministic retry, active-config exclusion, archive pin rejection, traversal rejection, missing credits, unexpected binaries and modified-install collisions.
- Windows PowerShell 5.1 importer and hidden wizard navigation tests pass. Default upgrade destination and lifecycle rollback/copy/uninstall regression tests pass.
- ModDB returns HTTP 403 to command-line downloads on the development machine. Automatic download and the real publisher archive layout remain unverified end-to-end; the ZIP picker is the fallback. Both previously recorded release identities remain pinned; the July 2026 release uses its publisher size/MD5, not an independently obtained SHA-256 pin.
- Clean installation, asset precedence, materials/models, GUI compatibility and live reset/snapshot acceptance remain for manual testing. Do not promote this experiment to a public release based on fixture checks alone.

Start with the opening Mars City sequence, mirrors/glass, door indicators, smoke and F11 lighting comparisons. Save a settings snapshot after a normal exit and verify that it contains the saved configuration. Record the exact installer revision and whether the ZIP picker or automatic download was used.
