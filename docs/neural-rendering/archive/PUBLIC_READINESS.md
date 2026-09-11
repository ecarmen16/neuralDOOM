# Public preview audit - 2026-09-11

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../README.md) for current guidance.

The maintainer requested publication of the latest installer/source and repository
visibility change. This is a preview, not a declaration of completed gameplay
acceptance. `main` remains at its reviewed checkpoint; release tags identify the
milestone branch source. No maintainer approvals, merges or main pushes are
performed by the release workflow.

## Source and artifact hygiene

- Current tracked-source/privacy checks pass. Personal settings, snapshot ZIPs,
  interrupted snapshot archives and local runtime/capture folders are excluded
  from Git; forced additions of settings are rejected by the source audit.
- Gitleaks 8.30.1 scanned all reachable Git history with redacted output: no
  credential findings. The local-only scanner was acquired from its official
  GitHub release, with SHA-256 checked; it is not bundled or a build dependency.
- The read-only `Test-PublicHistory.py` object audit found zero downstream
  personal-path/local-artifact locations. It also identified 35 inherited
  locations in old upstream release notes and FFmpeg documentation. Those
  locations predate this fork; they are retained upstream history rather than
  this project's private workspace data. Author credits and licenses remain.
  This audit complements secret scanning; it does not certify licensing.
- The previously published `internal-d16dab5e` ZIP and setup checksums were
  verified. Every ZIP member matched its manifest; its payload contained no
  retail resources, PK4s, runtime DLLs/add-ons or PDBs, and no personal profile
  paths were found in the ZIP or setup. The new package uses the same enforced
  source/binary/shader allowlist and privacy gate.
- Repository inventory showed no Actions runs/artifacts, wiki or Pages site.
  The only existing release was an internal prerelease. Publication must verify
  the new asset checksums and exact tag target before changing visibility.

## What is and is not shipped

The ZIP contains engine builds, compiled shaders and corresponding source,
including pinned submodule source and notices. Retail assets and optional
ReShade/RenoDX/NVIDIA runtimes are not in the release. Setup acquires optional
components on the player's machine; NR is explicitly experimental and is not an
official NVIDIA engine API. Runtime rebundling remains unapproved as documented
in [THIRD_PARTY_AND_LEGAL.md](../THIRD_PARTY_AND_LEGAL.md). Repository visibility
does not relax these constraints or approve a combined runtime bundle.

Snapshots are personal saved-setting exports, not public base presets. The
maintainer's tuned settings have not been adopted. A later confirmed baseline
must be selected after a full reset and sanitized before becoming install defaults.

## Validation limits

Settings snapshots passed isolated PowerShell 5.1/7 checks, including content
hashes, source preservation, exclusions, missing/active preset handling, existing
ZIP protection, pending-reset and running-game exclusion. The launcher passed
131 hidden state/event checks and visual bitmap inspection. The installer now
initializes its default upgrade destination to the detected installation; a
hidden constructor/navigation test covers the previously reported failure.

The renderer is unchanged from the previously built milestone checkpoint.
Reset/restart and broad visual acceptance still need player testing. Remaining
renderer findings are in [the accumulated review](REVIEW_2026-09-08.md); the
installer's default upgrade finding is corrected in this preview. No game was
launched during release preparation.
