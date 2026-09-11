# Known issues and troubleshooting

Milestone 1 includes experimental rendering features. Successful builds and automated checks do not establish artifact-free gameplay.

## Visual limitations

- Reduced-resolution DLSS presets can introduce pulsing or apparent movement on floors and other materials. Compare DLAA at native input resolution, then disable NR with F6 while preserving reconstruction to help isolate the effect.
- F11 lighting comparisons can reveal dark patches on some surfaces. Unsupported reflected materials replacing valid probe lighting is a confirmed code defect and a possible explanation; the specific reported scenes have not been verified.
- Mirrors, glass, smoke and animated emissives still need broader motion testing. Temporal mask framebuffer restoration, unused DLSS mask inputs and conditional material-stage selection remain open findings.
- NR can alter brightness and fine detail. Native HDR is unavailable with NR; use Native RTX or the DLAA/DLSS profile for native HDR.

These are tracked limitations, not claims that every material or scene exhibits each issue. Include the profile, reconstruction preset, map/location and exact comparison toggle when reporting a problem. See the [performance feedback guide](neural-rendering/PERFORMANCE_FEEDBACK.md).

## Settings and installation

Exit the game normally before saving a launcher settings snapshot. Snapshots export saved configuration, including ReShade/NR settings; they do not capture unsaved launcher selections and have no automatic restore feature. Finish a pending reset by launching and exiting before creating a snapshot.

The launcher reset includes ReShade/NR. The in-game reset changes game settings, including video, audio and controls. Both preserve saves and progress. Full in-game reset/restart acceptance remains pending; shipped defaults have not been replaced with a maintainer's personal tuning.

Use the setup EXE's Upgrade / repair option for an existing installation. The default upgrade destination defect found during review is fixed in M1, as are stale launch settings replayed by Restart Now and the reviewed menu-arrow offset defect. Setup logs are under local application data in `neuralDoom/SetupLogs`; game logs are under the installation's `captures/dogfood/base` directory. Review logs for personal paths before sharing them.

See the [player guide](PLAYING.md) for installation, controls and reset details.

## Developer limitations

The [September 8 review](neural-rendering/archive/REVIEW_2026-09-08.md) preserves evidence and proposed corrections. Its original statement that none of the findings had been fixed describes the review date, not the release.

Still open at M1:

- Temporal mask passes leave the wrong framebuffer active for subsequent alpha/debug draws.
- Unsupported reflected materials can suppress valid probe lighting.
- Conditional materials can lose a later active diffuse/emissive stage.
- Generated temporal masks are not consumed through the intended DLSS inputs; changing tag names alone is not a validated fix.
- Material declaration reload can leave dangling ray-stage cache pointers. Avoid live material reload with ray lighting until corrected.
- Legacy SSAO (`r_useNewSSAOPass 0`) has viewport assumptions incompatible with reduced-resolution rendering. The default modern path avoids this issue.
- Optional auto-exposure has inconsistent histogram encoding/decoding. Fixed exposure is the shipped default.

The [archived validation results](neural-rendering/archive/TEST_RESULTS.md) distinguish source/CPU checks from runtime observations. These findings have not been revalidated by this documentation-only cleanup.
