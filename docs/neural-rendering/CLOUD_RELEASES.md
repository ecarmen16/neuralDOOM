# Building release installers on GitHub

The `Build release installer` workflow uses standard `windows-2022` GitHub-hosted runners. Standard runners are [free for public repositories](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). It uses no paid larger runner, self-hosted machine or GPU. Temporary build artifacts are retained for seven days; the release assets remain attached to the release.

## Cut a release

Once this workflow is merged into `main`:

1. Finish testing and merge the release changes through the maintainer review process.
2. Create and push a version tag on that merged commit, for example `v0.2.0` or `milestone-2`. Tag names must start with `v` or `milestone-`, followed by a digit, and contain only letters, digits, dots, underscores and hyphens. Do not move a previously released tag.
3. The workflow builds both Release engines, runs offline installer/settings checks, packages corresponding source and compiled shaders, and creates the single-file setup EXE.
4. Open the resulting **draft release**. It contains the EXE, portable/source ZIP and a SHA-256 sidecar for each. Review the notes and publish it when ready.

Alternatively, use **Actions > Build release installer > Run workflow** and enter an existing tag from `main`. The workflow must exist on the default branch for the manual action to appear. Saving a draft in GitHub without pushing an actual tag does not trigger a build. This deliberately prepares the assets before publication, including for [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).

Existing published releases and populated drafts are never overwritten. If a run fails before upload, retry the run. If upload partially succeeds, inspect the draft and remove its incomplete asset set before retrying, or use a new version tag. Do not publish until all four assets are present. The workflow rechecks that the remote tag still identifies the built commit before uploading.

## What runs in the cloud

- Recursive checkout of the tag and pinned submodules; tags outside `main` are rejected.
- Official SHA-256-verified ISPC 1.31.0 and Streamline 2.12.0 build dependencies. Windows SDK/MSVC come from the hosted image. The default engine configuration remains SDK-off.
- Sequential native RTX and SDK-enabled DX12 Release builds, using the existing configure/build helpers and a neutral drive path. Shared shader outputs prohibit a concurrent build matrix in one checkout.
- Public-source audit, texture importer fixtures, hidden wizard/upgrade checks, lifecycle rollback and settings-snapshot checks.
- Existing source/EXE/shader manifest verification, prohibited-payload checks, ZIP integrity and setup `--verify`.
- Read-only build token; only the separate draft-upload job receives `contents: write`. No personal access token is needed. Action versions are pinned to commits.

No retail data, texture pack, NR runtime, ReShade or RenoDX is downloaded during the build. The official SDK is used for compilation and local build staging; its runtime DLLs are excluded from artifacts by the existing packager. Game content and optional components remain installation-time acquisitions from the user's machine/publisher.

Hosted runners do not validate GPU rendering or gameplay. Passing CI is not a substitute for the local visual test. Installers remain unsigned unless a separately approved signing mechanism is added.

## Local equivalent and current validation

From a clean Windows checkout with VS2022, a Windows SDK, CMake, Git and Python available, run:

```powershell
.\tools\neural-rendering\Build-CloudRelease.ps1 -RepoRoot <neutral-source-path> -Version v0.2.0
```

This downloads only the two build dependencies and writes artifacts under `releases/v0.2.0`. It does not upload anything. Use a new output version/directory for each attempt; the packager refuses to overwrite existing artifacts.

The existing local build/package path and recovered texture installer are verified. The workflow is newly added and requires its first GitHub-hosted run after the branch is approved and pushed; cloud execution is not yet claimed as passing.
