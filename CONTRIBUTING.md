# Contributing to neuralDoom

neuralDoom is the downstream project; RBDOOM-3-BFG remains its upstream source. Preserve original authorship, notices, and upstream history.

## Git layout

- `origin`: the configured downstream repository; inspect it with `git remote -v`.
- `upstream`: `https://github.com/RobertBeckebans/RBDOOM-3-BFG.git`.
- `main`: reviewed downstream checkpoints.
- `codex/…`: focused development branches. Do not rewrite upstream history to rename the project.

Milestone 1 optimization work uses **`codex/milestone-1`**. Keep its PR in draft
until review-ready. The latest changes require manual approval from `ecarmen16`
or `eraser851`; subsequent changes require another review. Those maintainers
perform the final merge. Agents must not approve, merge, enable auto-merge or
push milestone work directly to `main`, including through a maintainer's account.

Install the repository's commit and push checks once per checkout:

```powershell
git config core.hooksPath .githooks
```

Use your GitHub handle and GitHub no-reply email for project attribution. Set
`user.name` and `user.email` locally in this checkout before committing; check
both author and committer fields with `git log --format=fuller` before pushing.
Preserve upstream authorship and license notices.

The hook checks staged whitespace and staged source content. Game resources, captures, local SDK/NR runtimes, private staging folders and concrete machine paths must not enter commits. The checked-in ignore rules cover disposable artifacts without relying on `.git/info/exclude`. A source audit complements review; it is not a complete license or secret scanner.

The pre-push hook rejects updates and deletions targeting `main`; publish a
development branch and use the manually reviewed PR instead. Do not bypass the
hook. On 2026-09-07 GitHub returned HTTP 403 for branch protection/rulesets on this
private repository and required GitHub Pro or public visibility. Server-side
enforcement is therefore unavailable under the current plan. Keep the repository
private; the local hook and contributor policy are not equivalent to protection
on GitHub or on another checkout without hooks installed. If the account gains
support, require PR reviews from the maintainers, dismiss stale approvals, and
prevent direct/force pushes before claiming server enforcement.

## Build and verify

Keep shared checklists and plans suitable for any contributor. Personal account
names, availability, saved display calibration and local workspace histories
belong in ignored private notes. Use environment variables or placeholders for
paths. The source audit checks profile paths in both working and staged text;
the release packager also checks source, executable and shader bytes, including
UTF-16 strings. Run `Test-PublicPrivacy.py` when changing these gates.

Use [the unattended workflow](docs/neural-rendering/UNATTENDED_WORKFLOW.md). Run `Test-NeuralBuildIdentity.ps1`, appropriate SDK-OFF/ON builds, relevant gameplay/layout checks, and `git diff --check`. Record actual validation and limitations in the neural-rendering notes before committing renderer changes.

Keep retail data and optional local components outside the source-only checkout. The established local game installation can remain a separate build/test checkout. Do not stage or distribute its ignored payloads. Existing save-folder/config names remain compatible so branding changes do not hide player saves.

The upstream README content and original bootstrap script describe upstream setup and retain their historical names. The supported downstream executable is `neuralDoom.exe`; new source clones should use the repository name `neuralDoom`.
