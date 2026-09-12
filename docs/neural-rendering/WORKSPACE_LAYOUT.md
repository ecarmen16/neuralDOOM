# Workspace layout

The repository root contains source and build tools.

- `releases/`: generated setup EXE, alternative ZIP and checksum sidecars.
- `captures/neural/`: ignored local validation evidence and download caches.
- `neural-local/`: ignored private notes, backups and local archives. Never
  package this directory or commit its contents.
- `build-*`: generated build trees. Reconfigure after moving a checkout;
  compiler caches and local manifests can contain absolute paths.

Install test packages into a separate directory. Keep owned game data and local
runtime components outside tracked source. See [the player guide](../PLAYING.md) for the
installer flow and comparison controls.
