# Third-party, licensing, and distribution guardrails

This file is an engineering checklist, not legal advice.

## Current internal installer scope (2026-09-07)

The internal installer now offers separate Native, DLAA and experimental NR profiles. It contains our two engine configurations and their corresponding source, but no third-party runtime DLLs or add-ons. Components are obtained on the tester's machine, with explicit profile selection and optional local DLL selection (signed DLSS SR or the exact validated NR pin). This supersedes older notes below that describe a Native-only installer or prohibit all acquisition. Public redistribution of proprietary runtime binaries remains unapproved.

Reference: RHI `1402548741014161400929e7ee1a2a5de121af05`, especially [Renodx5AddonService.cs](https://github.com/RankFTW/RHI/blob/1402548741014161400929e7ee1a2a5de121af05/RenoDXCommander/Services/Renodx5AddonService.cs) and its `dlss_manifest.json`. RHI's GPL-3.0 source was inspected; no implementation code was copied. Our installer pins archives and exact extracted members in `tools/neural-rendering/neural-components.json`.

| Component | Acquisition and terms | Removal / updates |
|---|---|---|
| Streamline 2.12.0 | Official NVIDIA-RTX GitHub SDK. MIT-style framework `license.txt`; separate NVIDIA RTX terms for NGX/DLSS. Setup extracts three framework plugins and retains the included notices. | Optional SDK build; Native has no dependency. Version/hash updates require review. |
| DLSS SR 310.8.0 | Public RankFTW/rhi-repo release used by RHI, or locally selected NVIDIA-signed x64 DLL. Mirror archive has no bundled license; NVIDIA's RTX terms remain applicable, and mirror availability is not license verification. | Locally installed DLL only; no runtime in our package. |
| NR 310.8.SF-v2 and consumer add-on 4.70 | Public RankFTW/rhi-repo releases used by RHI, or the same hash-verified NR DLL selected locally. NR is a community-patched, unsigned runtime. The archives do not establish NR/add-on redistribution rights. The generic consumer's exact source/license correspondence remains unresolved. | Experimental internal compatibility option; no binary rebundling, no vendor support claim. |
| ReShade 6.8.0 add-on runtime | Official reshade.me installer, extracted without executing it. BSD-3-Clause upstream license. Renamed `neuraldoom-reshade64.dll`; no DXGI proxy. | Optional engine-loaded compatibility layer. |

Local installed notices include this record and the Streamline SDK's framework and NVIDIA terms. Hashes establish byte identity, and signatures establish the publisher; neither establishes permission to redistribute. Qualification for a public combined release remains outstanding. Disabling NR retains native DLAA at full resolution; switching to Native removes the runtime dependency altogether.

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

### Source reconnaissance record (2026-09-03)

| Project | Inspected revision | License observed | Role and current distribution decision |
|---|---|---|---|
| ReShade | `358c345ca2fe64f86e67c694f8379c356627adcb` | BSD-3-Clause in upstream `LICENSE.md`; add-on headers also identify BSD-3-Clause or MIT | Public runtime/add-on API reference. The compatibility loader accepts a user-local renamed runtime; no ReShade source or binary is tracked or distributed yet. |
| RenoDX | `66f4a40362cd7840bc0647734c434670539addb0` | MIT in upstream `LICENSE` | Public NGX hook utilities and ReShade add-on examples were inspected. The exact experimental DLSS5 generic add-on implementation was not present in the inspected public tree, so it is not reproduced or treated as an engine API. |
| RHI | `3fd79d9f8b0a776788f0c065aa2a130da283c31c` | GPL-3.0 in upstream `LICENSE` | Installer/manager reference only. It installs a ReShade proxy/add-on/configuration and launches the target; no RHI code or binary is integrated. |

The experimental `renodx-dlss5.addon64` and `nvngx_dlssnr.dll` remain unapproved for redistribution regardless of the licenses of the public manager/runtime projects around them.

## Local optional content record

### D3HDP BFG Lite

Local texture-installer branch (2026-09-11): the optional setup page credits **H3llBaron and the contributors credited in the original readme** and links the original project. It downloads or imports a pinned BFG Lite archive on the user's machine and preserves the original readme and credit documents under `notices/D3HDP-BFG-Lite`. This local acquisition does not grant permission to redistribute the pack; no assets are included in our installer payload or source. The local overlay experiment and validation limits are documented in [TEXTURE_INSTALLER_TEST.md](TEXTURE_INSTALLER_TEST.md).

| Field | Answer |
|---|---|
| Project/version | `D3HDP_BFG_Lite.zip`; previously inspected local release plus current July 2026 ModDB release |
| Canonical source | `https://www.moddb.com/mods/d3hdp-bfg-lite/downloads/d3hdp-bfg-lite` |
| License | Redistribution terms unresolved; archive contents are not approved for repository or release bundling |
| Runtime role | Optional local Doom 3 BFG visual/content mod selected with `fs_game mod_D3HDP_Lite` |
| Optional | The normal neuralDoom launcher and engine work without it |
| Binary redistribution | Not applicable to the inspected archive; content redistribution remains unresolved and blocked |
| Update strategy | Require a pinned release SHA-256 and re-inspect the complete archive manifest before accepting another version |
| Removal strategy | Delete the ignored local `mod_D3HDP_Lite/` folder and use `Launch-NeuralDoom.cmd` |

Local validation record:

- Previously inspected archive: 2,143,217,579 bytes; verified SHA-256 `E72ABB1C6C8C69FB28913D33709B298AC9553D4F52B10B0D02776BF00589BC4F`.
- Current ModDB page record (updated July 6, 2026): 2,143,408,902 bytes; publisher-hosted MD5 `1288283E5B0116EEA38BE993DA423725`.
- Setup downloads through ModDB into an ignored local cache or accepts a user-provided archive, validates the recognized release and all paths, and extracts only the isolated mod folder. It does not redistribute the archive through Git or a neuralDoom release.

## Lighting and ray-tracing investigation (2026-09-06)

- The official RBDOOM v1.6.0 release's `_rbdoom_global_illumination_data.pk4` was inspected and installed only into the local game checkout. It contains generated lighting textures/grid data, remains ignored, and is not approved for repository or release bundling. Exact source, contents and measured fingerprints are in [PROBE_LIGHTING.md](PROBE_LIGHTING.md).
- The new capability diagnostic uses the already vendored MIT-licensed NVRHI (`neo/extern/nvrhi/LICENSE.txt`) and adds no SDK dependency.
- NRD is only a candidate in [RAY_TRACING_PLAN.md](archive/RAY_TRACING_PLAN.md). Its current [NVIDIA RTX SDK license](https://raw.githubusercontent.com/NVIDIA-RTX/NRD/master/LICENSE.txt), including its open-source-combination restriction, requires compatibility/distribution review before incorporation. It must not be described as MIT merely because NVRHI is MIT. No NRD code or binary was downloaded or integrated.

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

## Local optional SDK record

### Existing NVRHI: local DX12 correctness patch (2026-09-06)

No new dependency was added for native ray diagnostics. The existing vendored
NVRHI retains its MIT notices and pinned submodule revision `dafbd407f6fb`.
`neo/cmake/NvrhiRayTracingFix.cmake` compiles a corrected copy of
`src/d3d12/d3d12-raytracing.cpp` in the build tree when RT is enabled, leaving
the submodule unchanged. It initializes the internal AS input
descriptor and set `DescsLayout = D3D12_ELEMENTS_LAYOUT_ARRAY` in
`SetInstanceDescs`. Native DX12 validation rejected the uninitialized TLAS layout
with message 1162. This two-line patch covers prebuild, initial build and update;
BLAS geometry still explicitly selects its existing array-of-pointers layout.
The helper rejects changed patch context when updating NVRHI so the workaround
can be reviewed then. No new vendor runtime is required.

### NVIDIA Streamline SDK 2.12.0

| Field | Answer |
|---|---|
| Project and version/commit | Streamline SDK `v2.12.0`; tag commit `e8aaa6eaac968711fb62473d4ae8256dde20919b` |
| Canonical source | `https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.12.0` |
| License | Streamline framework: MIT-style `license.txt`; NGX/DLSS components: separate `external/ngx-sdk/license.txt` and `bin/x64/nvngx_dlss.license.txt` NVIDIA RTX SDK terms |
| Build-time or runtime | Optional build headers/import library and runtime plugin/DLSS DLLs for private local DX12 testing |
| Optional | `USE_STREAMLINE=OFF` by default; `STREAMLINE_SDK_PATH` has no default and is required only when enabled |
| Binary redistribution | **Unresolved/blocked for this GPL project.** No NVIDIA binary is tracked, staged into Git, or approved for project distribution. |
| Source obligations | Preserve Streamline's MIT notice. NVIDIA SDK terms include notices, restrictions, and an open-source-license limitation that requires qualified legal review before distributing a combined binary. |
| Update strategy | Pin an official GitHub release tag, asset digest, programming guides, and licenses; do not use OTA/unversioned community packages for development baselines. |
| Removal strategy | Configure with `USE_STREAMLINE=OFF` and delete ignored `local-proprietary/streamline-v2.12.0`; the baseline has no SDK dependency. |

Local acquisition record:

- Official asset: `streamline-sdk-v2.12.0.zip`, 231,958,617 bytes.
- Vendor-published and verified SHA-256: `F5C0A3D870707DDDC3570FB4BCD3655CF48A8A68C3A9D342910CFA21B77DCF48`.
- Local ignored target: `local-proprietary/streamline-v2.12.0/`.
- The package and all DLLs remain untracked. Using the NGX/DLSS components is subject to NVIDIA's included terms; this engineering record is not legal advice.


## 2026-09-07 - Native internal Release package

The internal package uses the SDK-free DX12/RTX Release configuration, with the corresponding tracked source and recursively pinned submodule source included in the same ZIP. Original GPL/additional-license/dependency notices remain alongside source. No new dependency is integrated. The packaging allowlist consists of this source, the exact native executable and manifest-verified compiled shaders. Unused upstream prebuilt formatter/OpenAL/FFmpeg binaries and import libraries are omitted. The documented build has FFMPEG off and uses Windows XAudio, not the omitted OpenAL binary.

No retail resources, lighting/mod packs, NVIDIA DLLs, ReShade/RenoDX add-ons or PDBs are included. The installer imports owned game data and the separately obtained, fingerprint-verified lighting pack locally after extraction. It links to Microsoft's official VC++ x64 Redistributable when needed instead of redistributing a runtime installer. DLAA/NR distribution remains blocked as recorded above. Source setup no longer downloads/copies an NR runtime from an arbitrary path or URL.


## 2026-09-07 - Automatic publisher downloads

`Setup-Dependencies.ps1` obtains the already-reviewed RBDOOM 1.6.0 archive from its original GitHub release and extracts only the fingerprint-verified lighting pack. Archive/pack hashes remain those in PROBE_LIGHTING.md. These files are cached locally, not bundled or tracked.

New setup-only helper: official 7-Zip standalone `7zr.exe` release 26.03 from `https://github.com/ip7z/7zip/releases/download/26.03/7zr.exe`, 602624 bytes, SHA-256 `AD4C82FADCBDF93C03B4FC440F300509C7D60C5C2F4D183E35D9D70D6957037D`. The [publisher license](https://www.7-zip.org/license.txt) describes LGPL-2.1-or-later for the standalone files. This executable is downloaded directly into the installation cache, never linked into the engine or bundled in our artifacts. Updates require an explicit version/hash review; removal is deleting the setup cache. No runtime dependency is added to the game.

The Microsoft VC++ prerequisite is downloaded from its official HTTPS endpoint when missing and must pass valid Microsoft-publisher Authenticode verification before execution. It is not bundled. Setup accepts success/already-installed/restart-required codes and never restarts Windows itself. The Windows .NET Framework supplies the setup bootstrap compiler/runtime; its binary is not redistributed. The bootstrap's GPL source accompanies the embedded package. DLAA/NR runtime restrictions remain unchanged.
