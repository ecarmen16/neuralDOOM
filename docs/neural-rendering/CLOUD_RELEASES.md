# Building release installers on GitHub

The `Build release installer` workflow uses standard `windows-2022` GitHub-hosted runners. Standard runners are [free for public repositories](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). It uses no paid larger runner, self-hosted machine or GPU. Temporary build artifacts are retained for seven days; the release assets remain attached to the release.

## Cut a release

Once this workflow is merged into `main`:

1. Finish testing and merge the release changes through the pull-request review process.
2. Create and push a version tag on that merged commit, for example `v0.2.0` or `milestone-2`. Tag names must start with `v` or `milestone-`, followed by a digit, and contain only letters, digits, dots, underscores and hyphens. Do not move a previously released tag.
3. The workflow builds both Release engines, runs offline installer/settings checks, packages corresponding source and compiled shaders, and creates the single-file setup EXE.
4. Open the resulting **draft release**. It contains the EXE, portable/source ZIP and a SHA-256 sidecar for each. Review the notes and publish it when ready. If you already published the release through GitHub when creating the tag, the action attaches the same four files to that release.

Alternatively, use **Actions > Build release installer > Run workflow** and enter an existing tag from `main`. The workflow must exist on the default branch for the manual action to appear. Saving a draft in GitHub without pushing an actual tag does not trigger a build. This deliberately prepares the assets before publication, including for [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).

Existing assets are never overwritten. The uploader accepts both drafts and published releases, verifies the local checksums and remote tag commit, and compares existing asset SHA-256 digests before uploading anything. Identical files are skipped; missing files are attached. Conflicting files or unavailable digests stop the upload. A partial upload can therefore be retried with the same verified artifact set. GitHub-locked immutable releases cannot receive missing files; prepare their assets before publication.

A source/workflow bug requires a reviewed fix and a new tag on the merged commit: rerunning the old tag still builds its old source. An upload-only failure does not require rebuilding or deleting releases: download the successful run's `release-installer` artifact and run `Publish-ReleaseAssets.ps1` with its repository, tag, exact source commit and artifact directory. Do not move released tags.

## What runs in the cloud

- Recursive checkout of the tag and pinned submodules; tags outside `main` are rejected.
- Official SHA-256-verified ISPC 1.31.0 and Streamline 2.12.0 build dependencies. Windows SDK/MSVC come from the hosted image. The default engine configuration remains SDK-off.
- Sequential native RTX and SDK-enabled DX12 Release builds, using the existing configure/build helpers and a neutral drive path. Shared shader outputs prohibit a concurrent build matrix in one checkout.
- Public-source audit, texture importer fixtures, hidden wizard/upgrade checks, lifecycle rollback and settings-snapshot checks.
- Existing source/EXE/shader manifest verification, prohibited-payload checks, ZIP integrity and setup `--verify`.
- Read-only build token; only the separate asset-upload job receives `contents: write`. No personal access token is needed. Action versions are pinned to commits.

No retail data, texture pack, NR runtime, ReShade or RenoDX is downloaded during the build. The official SDK is used for compilation and local build staging; its runtime DLLs are excluded from artifacts by the existing packager. Game content and optional components remain installation-time acquisitions from the user's machine/publisher.

Hosted runners do not validate GPU rendering or gameplay. Passing CI is not a substitute for the local visual test. Installers remain unsigned unless a separately approved signing mechanism is added.

## Local equivalent and current validation

From a clean Windows checkout with VS2022, a Windows SDK, CMake, Git and Python available, run:

```powershell
.\tools\neural-rendering\Build-CloudRelease.ps1 -RepoRoot <neutral-source-path> -Version v0.2.0
```

This downloads only the two build dependencies and writes artifacts under `releases/v0.2.0`. It does not upload anything. Use a new output version/directory for each attempt; the packager refuses to overwrite existing artifacts.

## Automated checks

`Test-PublicSourceAudit.ps1` checks ordinary and mapped-root source audits. `Test-ReleaseAssetUpload.ps1` checks uploads to drafts and published releases, retries, matching hashes, immutable releases and invalid artifacts. Both run on workflow pull requests and before release builds.
