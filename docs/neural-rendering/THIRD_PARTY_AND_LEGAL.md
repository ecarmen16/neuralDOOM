# Third-party, licensing, and distribution guardrails

This file is an engineering checklist, not legal advice.

## RBDOOM-3-BFG and Doom 3 BFG data

- RBDOOM-3-BFG source is published under GPLv3 with project-specific exceptions/additional terms described by its repository.
- The source repository does not grant permission to redistribute Doom 3 BFG retail game data.
- Keep retail `.resources`, videos, maps, textures, sounds, and other copied data local.
- The helper copies local game data only because RBDOOM requires a legally owned installation to run. It adds copied untracked files to `.git/info/exclude`, not to the tracked `.gitignore`.
- Before publishing binaries, verify GPL source-offer and attribution requirements and review `LICENSE.md` and `LICENSE_EXCEPTIONS.md` at the exact upstream revision used.

## NVIDIA SDKs and runtimes

- Use only public, official SDK packages under terms that permit the intended development and distribution.
- Do not commit an SDK merely because it is downloadable. Prefer a documented acquisition step or an approved package/submodule arrangement after license review.
- Do not distribute any runtime extracted from a commercial game, leaked before public release, private beta package, or another user's installation.
- Keep any local experimental runtime in a directory such as `local-proprietary/`, which is excluded from Git.
- An engine integration should compile and run without optional NVIDIA components when the associated CMake option is OFF.

## ReShade, RenoDX, and DLSS5-Feeder

- Treat the feeder/RenoDX route as an external local proof of concept until each component's current license and redistribution rules are reviewed.
- Do not bundle these tools into an RBDOOM release by default.
- Document required versions and configuration, but link users to the original projects rather than repackaging binaries.
- Never imply that an unofficial mod path is an NVIDIA-supported DLSS 5 integration.

## Dependency review template

Before adding a dependency, record:

| Field | Required answer |
|---|---|
| Project and version/commit | Exact immutable identifier |
| Canonical source | Official repository or vendor page |
| License | Name plus bundled license-file path |
| Build-time or runtime | Which and why |
| Optional | How a no-dependency build remains available |
| Binary redistribution | Explicitly permitted, prohibited, or unresolved |
| Source obligations | Notices, source delivery, modifications, patent terms |
| Update strategy | How current security/compatibility changes are reviewed |
| Removal strategy | How the integration can be disabled or removed |

No dependency is approved merely by filling out the table; unresolved terms block distribution.

## Local build dependency record

### Intel Implicit SPMD Program Compiler (ISPC) v1.31.0

| Field | Answer |
|---|---|
| Project and version/commit | ISPC v1.31.0 (`c6adb4f` release commit) |
| Canonical source | `https://github.com/ispc/ispc/releases/tag/v1.31.0` |
| License | BSD-3-Clause; upstream `LICENSE.txt` |
| Build-time or runtime | Build-time compiler for `neo/libs/ispc_texcomp/kernel.ispc`; not a game runtime dependency |
| Optional | Required by the current upstream build, but installed locally under ignored `tools/ispc/` |
| Binary redistribution | Not included in this repository or planned RBDOOM artifacts |
| Source obligations | Preserve upstream license if redistributed separately; no binary is tracked here |
| Update strategy | Pin the downloaded Windows archive and verify its published SHA-256 before local installation |
| Removal strategy | Delete the ignored local `tools/ispc/` directory; no tracked source depends on a bundled binary |

Local acquisition record:

- Archive: `ispc-v1.31.0-windows.zip`
- Official URL: `https://github.com/ispc/ispc/releases/download/v1.31.0/ispc-v1.31.0-windows.zip`
- Expected SHA-256: `9A18793800B91D5BE7B851513672CD9A81A985A5A5DFEC5611C2318E8AD4140A`
- Installation target: ignored local path `tools/ispc/bin/ispc.exe`

## Local diagnostic-tool record

### RenderDoc 1.46

- Installed system-wide through Winget package `BaldurKarlsson.RenderDoc` from the official RenderDoc MSI.
- RenderDoc is MIT-licensed and is used only for local DX12 frame capture/debugging.
- It is not a build dependency, runtime dependency, tracked binary, or redistribution component of this project.
- Captures remain local under ignored paths and must be checked for proprietary game content before any sharing.
