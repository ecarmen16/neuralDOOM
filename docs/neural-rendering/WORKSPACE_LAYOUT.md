# Local workspace and installer handoff

The repository root is the source checkout. Keep the upstream source layout and
the historical development plans in `docs/neural-rendering` intact for reference.

- `releases/`: current setup EXE, alternative ZIP, and SHA-256 sidecars. Generated,
  ignored by Git; run the setup EXE to install into a separate empty folder.
- `captures/neural/`: local test evidence and download caches. Not release inputs.
- `neural-local/archive/desktop-DOOM3R/`: preserved former Desktop workspace,
  including the original starter plans, local saves/settings, screenshots, Git
  history, and development files. Local reference only; never package or commit it.

The archived checkout's old build caches and shortcuts contain their former
absolute paths. Do not launch or build from those stale caches; configure a fresh
build in the source checkout for future development. Keep the archive until any
desired saves and locally managed components have been accounted for.

The graphical installer wizard offers a versioned destination independently of
the owned BFG data source. It performs supporting downloads and extraction, then
creates a Start menu entry and optional desktop shortcut. It does not launch the game. See `INTERNAL_TESTING.md` at the repository
root for the controls and acceptance checklist.
