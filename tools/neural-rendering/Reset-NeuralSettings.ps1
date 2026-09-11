# Launcher-only full preference reset. Confirmation belongs to the caller.
# Profile progress is preserved by the engine's one-shot preference reset;
# profile.bin must never be deleted or edited as an opaque binary here.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NeuralSettingsResetPath {
    param([string]$Root, [string]$Relative)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not $Relative -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match ':|(^|[/\\])\.\.([/\\]|$)') { throw 'Unsafe settings path.' }
    $path = [IO.Path]::GetFullPath((Join-Path $rootPath $Relative))
    if (-not $path.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe settings path.' }
    for ($parent = $path; $parent; $parent = Split-Path -Parent $parent) {
        $item = Get-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Settings reset cannot follow linked paths.' }
    }
    return $path
}

function New-NeuralSettingsResetGuard {
    param([string]$Name = 'DOOM3', [string]$Action = 'restoring defaults')
    # Hold the named object throughout the transaction so the engine's own
    # single-instance check also prevents a launch racing this operation.
    $created = $false
    $guard = New-Object Threading.Mutex($false, $Name, [ref]$created)
    if (-not $created) { $guard.Dispose(); throw "Close Doom 3 before $Action." }
    return $guard
}

function Reset-NeuralGameSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    if ($root -eq [IO.Path]::GetPathRoot($root).TrimEnd('\', '/') -or
        -not (Test-Path -LiteralPath (Get-NeuralSettingsResetPath $root 'base/default.cfg') -PathType Leaf)) {
        throw 'Choose a neuralDoom installation containing its shipped base/default.cfg.'
    }
    $guard = New-NeuralSettingsResetGuard
    try {
        $remove = @(
            'captures/dogfood/base/D3BFGConfig.cfg', 'base/D3BFGConfig.cfg',
            'captures/dogfood/base/autoexec.cfg', 'base/autoexec.cfg',
            'captures/dogfood/base/default.cfg', 'captures/dogfood/base/joy_360_0.cfg',
            'captures/dogfood/base/joy_lefty.cfg', 'captures/dogfood/base/joy_righty.cfg',
            'captures/dogfood/base/neural_dogfood.cfg',
            'captures/dogfood/installed-profile.pending',
            'captures/dogfood/settings-doom-contrast-v1.applied',
            'ReShadePreset.ini', 'imgui.ini'
        )
        $marker = 'captures/dogfood/base/neural_settings_reset.pending'
        $profile = 'captures/dogfood/base/savegame/profile.bin'
        $ini = Get-NeuralSettingsResetPath $root 'reshade.ini'
        $resetNR = (Test-Path -LiteralPath $ini) -or
            (Test-Path -LiteralPath (Get-NeuralSettingsResetPath $root 'neuraldoom-reshade64.dll'))
        $targets = @($remove) + @($marker, $profile, 'base/savegame/profile.bin')
        if ($resetNR) { $targets += 'reshade.ini' }
        # Validate every exact target before creating the backup or changing files.
        $before = @{}
        foreach ($relative in $targets) {
            $path = Get-NeuralSettingsResetPath $root $relative
            if (Test-Path -LiteralPath $path) {
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Settings path is a directory: $relative" }
                $before[$relative] = [IO.File]::ReadAllBytes($path)
            }
        }
        # These archived flags are unlock progress, including in CFG-only saves.
        # The engine also preserves them when it loads and resets profile prefs.
        $unlocks = @{}
        foreach ($relative in @('base/D3BFGConfig.cfg', 'captures/dogfood/base/D3BFGConfig.cfg')) {
            if (-not $before.ContainsKey($relative)) { continue }
            $text = [Text.Encoding]::UTF8.GetString($before[$relative])
            foreach ($match in [regex]::Matches($text, '(?im)^\s*seta?\s+(g_nightmare|g_roeNightmare|g_leNightmare)\s+"?1"?[ \t]*(?://[^\r\n]*)?\r?$')) {
                $unlocks[$match.Groups[1].Value] = $true
            }
        }
        $writes = @{}
        $writes[$marker] = [Text.Encoding]::ASCII.GetBytes("version1`r`n")
        if ($unlocks.Count) {
            $lines = @('// Preserved campaign unlocks; other preferences restore on next launch.')
            foreach ($name in @('g_nightmare', 'g_roeNightmare', 'g_leNightmare')) {
                if ($unlocks.ContainsKey($name)) { $lines += 'set ' + $name + ' "1"' }
            }
            $writes['captures/dogfood/base/D3BFGConfig.cfg'] = [Text.Encoding]::ASCII.GetBytes(($lines -join "`r`n") + "`r`n")
        }
        if ($resetNR) {
            . (Join-Path $PSScriptRoot 'EmbeddedNR.ps1')
            # Identical seed to Setup-NeuralComponents: use runtime defaults for
            # appearance, with only our shipped INPUT/NR integration contract.
            $text = "[INPUT]`r`nKeyOverlay=36,0,0,0`r`nKeyEffects=0,0,0,0`r`n[RenoDX.DLSS5]`r`n"
            $writes['reshade.ini'] = (New-Object Text.UTF8Encoding $false).GetBytes((Get-NeuralNRFullResolutionConfig -Text $text))
        }
        $backupRelative = '.neuraldoom-cache/settings-reset/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
        $backup = Get-NeuralSettingsResetPath $root ($backupRelative + '/reset.json') | Split-Path -Parent
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        $records = @(foreach ($relative in $before.Keys | Sort-Object) {
            $copy = Get-NeuralSettingsResetPath $backup $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null
            [IO.File]::WriteAllBytes($copy, $before[$relative])
            @{ path = $relative; sha256 = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash }
        })
        $journal = @{ schemaVersion = 1; status = 'prepared'; files = $records; changedPaths = @(); preserves = 'Save games, profile statistics, achievements and campaign unlocks' }
        $journalPath = Join-Path $backup 'reset.json'
        $journal | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journalPath -Encoding UTF8
        $changed = New-Object 'Collections.Generic.List[string]'
        try {
            foreach ($relative in @($remove) + @($writes.Keys) | Select-Object -Unique) {
                $path = Get-NeuralSettingsResetPath $root $relative
                if ($writes.ContainsKey($relative)) {
                    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
                    # Write to a sibling first, then replace atomically. A failed
                    # write cannot truncate either the active settings or backup.
                    $temporary = $path + '.reset-' + [guid]::NewGuid().ToString('N') + '.tmp'
                    try {
                        [IO.File]::WriteAllBytes($temporary, $writes[$relative])
                        if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temporary, $path, [NullString]::Value) }
                        else { [IO.File]::Move($temporary, $path) }
                    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
                    $changed.Add($relative)
                } elseif (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Force
                    $changed.Add($relative)
                }
            }
            $journal.status = 'complete'; $journal.changedPaths = @($changed.ToArray())
            $journal | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journalPath -Encoding UTF8
        } catch {
            $failure = $_
            $restoreErrors = @()
            foreach ($relative in $changed) {
                try {
                    $path = Get-NeuralSettingsResetPath $root $relative
                    if ($before.ContainsKey($relative)) { [IO.File]::WriteAllBytes($path, $before[$relative]) }
                    elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
                } catch { $restoreErrors += $_.Exception.Message }
            }
            $journal.status = if ($restoreErrors.Count) { 'restore-incomplete' } else { 'restored-after-failure' }
            $journal.changedPaths = @($changed.ToArray())
            $journal | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journalPath -Encoding UTF8
            if ($restoreErrors.Count) { throw "Reset failed and some settings could not be restored. Backups: $backup. $($restoreErrors -join ' ')" }
            throw $failure
        }
        return $backup
    } finally { $guard.Dispose() }
}
