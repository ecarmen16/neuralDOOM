# Personal, local settings exports. Never add these ZIPs to source or releases.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Reset-NeuralSettings.ps1')

function Save-NeuralSettingsSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Destination)
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    if ($root.StartsWith('\\')) { throw 'Settings snapshots require a local installation.' }
    if (-not (Test-Path -LiteralPath (Get-NeuralSettingsResetPath $root 'base/default.cfg') -PathType Leaf)) {
        throw 'Choose a neuralDoom installation containing base/default.cfg.'
    }
    $output = [IO.Path]::GetFullPath($Destination)
    if ($output.StartsWith('\\')) { throw 'Save the personal snapshot to a local folder.' }
    if ([IO.Path]::GetExtension($output) -ine '.zip') { throw 'Settings snapshots must use a .zip filename.' }
    if (Test-Path -LiteralPath $output) { throw 'That snapshot already exists. Choose a new filename to keep both versions.' }
    for ($parent = Split-Path -Parent $output; $parent; $parent = Split-Path -Parent $parent) {
        $item = Get-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Settings snapshots cannot follow linked output folders.' }
    }
    $guard = New-NeuralSettingsResetGuard -Action 'saving a settings snapshot; the game must finish writing its settings first'
    try {
        if (Test-Path -LiteralPath (Get-NeuralSettingsResetPath $root 'captures/dogfood/base/neural_settings_reset.pending')) {
            throw 'Finish the pending reset by launching and exiting Doom 3 before saving a settings snapshot.'
        }
        $paths = @(
            'captures/dogfood/base/D3BFGConfig.cfg', 'base/D3BFGConfig.cfg',
            'captures/dogfood/base/autoexec.cfg', 'base/autoexec.cfg',
            'captures/dogfood/base/default.cfg', 'captures/dogfood/base/joy_360_0.cfg',
            'captures/dogfood/base/joy_lefty.cfg', 'captures/dogfood/base/joy_righty.cfg',
            'reshade.ini', 'ReShadePreset.ini', 'imgui.ini'
        )
        $contents = [ordered]@{}
        $warnings = @()
        foreach ($relative in $paths) {
            $path = Get-NeuralSettingsResetPath $root $relative
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $item = Get-Item -LiteralPath $path
            if ($item.PSIsContainer -or $item.Length -gt 4MB) { throw "Not a supported settings file: $relative" }
            $contents[$relative] = [IO.File]::ReadAllBytes($path)
        }
        if (-not $contents.Contains('captures/dogfood/base/D3BFGConfig.cfg') -and -not $contents.Contains('base/D3BFGConfig.cfg')) {
            throw 'No saved game configuration exists yet. Launch and exit Doom 3 before taking a snapshot.'
        }
        # Capture only the explicitly active ReShade INI, never shader folders,
        # presets mentioned in arbitrary keys, runtime DLLs, or recursive execs.
        $activePreset = $null
        if ($contents.Contains('reshade.ini')) {
            $section = ''
            $iniText = [Text.Encoding]::UTF8.GetString($contents['reshade.ini']).TrimStart([char]0xFEFF)
            foreach ($line in $iniText -split '\r?\n') {
                if ($line -match '^\s*\[([^\]]+)\]\s*$') { $section = $Matches[1]; continue }
                if ($section -ieq 'GENERAL' -and $line -match '^\s*PresetPath\s*=\s*(.*?)\s*$') { $activePreset = $Matches[1].Trim('"') }
            }
        }
        if ($activePreset) {
            $presetPath = if ([IO.Path]::IsPathRooted($activePreset)) { [IO.Path]::GetFullPath($activePreset) } else { [IO.Path]::GetFullPath((Join-Path $root $activePreset)) }
            if ($presetPath.StartsWith('\\')) { throw 'Settings snapshots cannot read a network preset reference.' }
            # A preset outside the install is an explicit settings reference;
            # capture that one INI under a fixed ZIP name without following links.
            if ([IO.Path]::GetExtension($presetPath) -ine '.ini') { throw 'The active ReShade preset is not an INI file.' }
            for ($parent = $presetPath; $parent; $parent = Split-Path -Parent $parent) {
                $item = Get-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
                if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Settings snapshots cannot follow linked preset paths.' }
            }
            if (-not (Test-Path -LiteralPath $presetPath)) {
                # ReShade writes a default PresetPath even when no effects preset
                # has been created. NR controls still live in reshade.ini.
                $warnings += 'The referenced ReShade effects preset does not exist. NR settings from reshade.ini are included.'
            } elseif (-not (Test-Path -LiteralPath $presetPath -PathType Leaf) -or (Get-Item -LiteralPath $presetPath).Length -gt 4MB) {
                throw 'The active ReShade preset is not a supported settings file.'
            } else {
                $contents['active-preset/reshade-preset.ini'] = [IO.File]::ReadAllBytes($presetPath)
            }
        }
        $revision = ''
        $revisionPath = Get-NeuralSettingsResetPath $root 'SOURCE_REVISION.txt'
        if (Test-Path -LiteralPath $revisionPath -PathType Leaf) {
            $first = Get-Content -LiteralPath $revisionPath -TotalCount 1
            if ($first -match '^[0-9a-fA-F]{40}$') { $revision = $first }
        }
        $hasher = [Security.Cryptography.SHA256]::Create()
        try {
            $records = @(foreach ($relative in $contents.Keys) {
                @{ path = $relative; bytes = $contents[$relative].Length; sha256 = [BitConverter]::ToString($hasher.ComputeHash($contents[$relative])).Replace('-', '') }
            })
        } finally { $hasher.Dispose() }
        $manifest = [ordered]@{
            schemaVersion = 1; type = 'neuralDoom-settings-snapshot'; createdUtc = [DateTime]::UtcNow.ToString('o')
            sourceRevision = $revision; files = $records; activePresetReference = $activePreset
            warnings = $warnings
            scope = 'Last saved game configuration/bindings and ReShade/NR settings. Unsaved launcher selections are not applied.'
            excluded = @('savegames', 'profile.bin (contains progress)', 'runtime binaries', 'shaders', 'logs', 'screenshots', 'pending reset and launch commands')
            privacy = 'Personal backup; settings may contain local paths. Not a distributable base preset. No automatic restore is provided.'
        }
        $contents['snapshot.json'] = (New-Object Text.UTF8Encoding $false).GetBytes(($manifest | ConvertTo-Json -Depth 6))
        Add-Type -AssemblyName System.IO.Compression
        $parent = Split-Path -Parent $output
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        # Finish the ZIP privately before publishing it. Never truncate an older snapshot.
        $temporary = Join-Path $parent ('.neuraldoom-snapshot-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            try {
                $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
                try {
                    foreach ($relative in $contents.Keys) {
                        $entry = $zip.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
                        $writer = $entry.Open()
                        try { $bytes = $contents[$relative]; $writer.Write($bytes, 0, $bytes.Length) } finally { $writer.Dispose() }
                    }
                } finally { $zip.Dispose() }
            } finally { $stream.Dispose() }
            [IO.File]::Move($temporary, $output)
        } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
        return [pscustomobject]@{ Path = $output; Warnings = $warnings; FileCount = $records.Count }
    } finally { $guard.Dispose() }
}
