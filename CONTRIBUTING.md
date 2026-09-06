# Contributing to neuralDoom

neuralDoom is the downstream project; RBDOOM-3-BFG remains its upstream source. Preserve original authorship, notices, and upstream history.

## Git layout

- Intended downstream repository: `ecarmen16/neuralDoom`.
- `origin`: `https://github.com/ecarmen16/neuralDoom.git`.
- `upstream`: `https://github.com/RobertBeckebans/RBDOOM-3-BFG.git`.
- `main`: reviewed downstream checkpoints.
- `codex/…`: focused development branches. Do not rewrite upstream history to rename the project.

Install the repository's commit checks once per checkout:

```powershell
git config core.hooksPath .githooks
```

The hook checks staged whitespace and staged source content. Game resources, captures, local SDK/NR runtimes, private staging folders and concrete machine paths must not enter commits. The checked-in ignore rules cover disposable artifacts without relying on `.git/info/exclude`. A source audit complements review; it is not a complete license or secret scanner.

## Build and verify

Use [the unattended workflow](docs/neural-rendering/UNATTENDED_WORKFLOW.md). Run `Test-NeuralBuildIdentity.ps1`, appropriate SDK-OFF/ON builds, relevant gameplay/layout checks, and `git diff --check`. Record actual validation and limitations in the neural-rendering notes before committing renderer changes.

Keep retail data and optional local components outside the source-only checkout. The established local game installation can remain a separate build/test checkout. Do not stage or distribute its ignored payloads. Existing save-folder/config names remain compatible so branding changes do not hide player saves.

The upstream README content and original bootstrap script describe upstream setup and retain their historical names. The supported downstream executable is `neuralDoom.exe`; new source clones should use the repository name `neuralDoom`.
