# Release packaging

Player instructions have moved to the [installation, settings and controls guide](docs/PLAYING.md). This filename is retained for existing release tooling and links.

## Install or manage

See [installation and upgrade instructions](docs/PLAYING.md#install-or-manage).

## Exact comparison controls

See [rendering controls](docs/PLAYING.md#exact-comparison-controls) and [snapshots and resets](docs/PLAYING.md#settings-snapshots-and-resets).

## Release packaging

For a hosted build, see [GitHub release automation](docs/neural-rendering/CLOUD_RELEASES.md). Pushing a version tag builds an installer and attaches assets to the existing release, or creates a draft if none exists. The manual local process follows.

Commit source, synchronize the local build checkout to that exact commit, configure DX12 with `-RayTracing ON` and SDK off, then run `Build-RBDOOM.ps1 -Configuration Release -BuildDirectory <native-build-rt>`. From a Python 3 environment:

```text
python tools/neural-rendering/Build-InternalPackage.py --source <clean-source-checkout> --game <matching-build-checkout> --output <new-output.zip> --build-directory <native-release-build> --neural-build-directory <neural-release-build>
```

The packager requires clean matching commits, initialized pinned submodules, a Release/native-RTX manifest, matching EXE/shaders and no debug CRT imports. Native must be SDK-free; the optional second engine must use the same source and shaders with Streamline enabled. It includes Git-tracked source and recursive submodule source, omits unused upstream prebuilt tools/import libraries, and rejects DLLs, PDBs, retail resources and PK4s. It never recursively copies the game folder. The ZIP has a SHA-256 sidecar and `internal-package.json` hashes; the installer converts portable build identity only after verification. Unsigned test builds may prompt through Windows SmartScreen; the hash establishes artifact identity, not publisher signing.

Release diagnostic strings must not embed a personal profile path. Build from a
neutral source location; on Windows, an unused temporary `subst` drive can map
the source checkout while configuring and building a fresh `build-private-release`
tree. Keep that mapping active through packaging and remove it afterward. Pass
`--build-directory <release-build-directory>` when packaging this alternate tree.
The packager rejects personal profile paths in every payload entry, including
ASCII and UTF-16 strings inside binaries. This does not replace a license or
secret review.

Source rebuild instructions and license notices remain in README.md, LICENSE.md, LICENSE_EXCEPTIONS.md, COPYING.txt where present, and dependency source directories. Optional upstream prebuilt tools omitted from the ZIP are not required by the documented DX12/FFMPEG-off/XAudio build. The included source has expanded submodules; a Git clone should use `--recursive` instead.

When rebuilding directly from the exported source without Git metadata, use the documented CMake configure options and `cmake --build build-rt --config Release`. The Build-RBDOOM manifest helper requires a Git checkout; the raw CMake build does not create launcher identity files.

To wrap the verified ZIP as the single-file setup:

```powershell
.\tools\neural-rendering\Build-InternalSetup.ps1 -PackagePath <package.zip> -OutputPath <new-setup.exe>
```

This uses the Windows .NET Framework compiler and embeds the ZIP plus its matching bootstrap source. `setup.exe --verify` validates/extracts the embedded payload in a temporary folder without installing, downloading or launching the game. The EXE also has a SHA-256 sidecar. Publisher sources: [RBDOOM release](https://github.com/RobertBeckebans/RBDOOM-3-BFG/releases/tag/v1.6.0), [7-Zip downloads](https://www.7-zip.org/download.html), [Microsoft runtime](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).
