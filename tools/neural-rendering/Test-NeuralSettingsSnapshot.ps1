[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Save-NeuralSettingsSnapshot.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('../../captures/neural/settings-snapshot-' + [guid]::NewGuid().ToString('N'))))
$root = Join-Path $fixture 'install'
$script:snapshotGuard = ${function:New-NeuralSettingsResetGuard}
$script:snapshotMutex = 'neuralDoom-snapshot-test-' + [guid]::NewGuid().ToString('N')
function New-NeuralSettingsResetGuard { param([string]$Action) & $script:snapshotGuard -Name $script:snapshotMutex -Action $Action }
function Put-SnapshotFile([string]$Name, [string]$Text) {
    $path = Join-Path $root $Name
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $Text)
}
function Read-SnapshotZip([string]$Path) {
    $files = @{}
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $zip.Entries) {
            $reader = $entry.Open(); $copy = New-Object IO.MemoryStream
            try { $reader.CopyTo($copy); $files[$entry.FullName] = $copy.ToArray() } finally { $reader.Dispose(); $copy.Dispose() }
        }
    } finally { $zip.Dispose() }
    return $files
}
function Expect-SnapshotFailure([string]$Name, [string]$Message) {
    $path = Join-Path $fixture ($Name + '.zip')
    $caught = $false
    try { Save-NeuralSettingsSnapshot -RepoRoot $root -Destination $path | Out-Null } catch { if ($_.Exception.Message -notlike $Message) { throw }; $caught = $true }
    if (-not $caught -or (Test-Path -LiteralPath $path)) { throw 'Failed snapshot left a published ZIP or did not reject the input.' }
}
Put-SnapshotFile 'base/default.cfg' 'shipped controls'
Put-SnapshotFile 'captures/dogfood/base/D3BFGConfig.cfg' "set r_neuralNRReconstructionMode 4`r`nbind F11 rayTracingToggle"
Put-SnapshotFile 'captures/dogfood/base/autoexec.cfg' 'set r_exposure 0.7'
Put-SnapshotFile 'reshade.ini' "[GENERAL]`r`nPresetPath=custom/effects.ini`r`n[RenoDX.DLSS5]`r`nNeuralUplift=1`r`nNRIntensity=0.8"
Put-SnapshotFile 'custom/effects.ini' "[Fake.fx]`nStrength=0.25"
Put-SnapshotFile 'imgui.ini' 'overlay layout'
Put-SnapshotFile 'captures/dogfood/base/savegame/profile.bin' 'private profile progress'
Put-SnapshotFile 'captures/dogfood/base/savegame/GAME-quick/savegame.dat' 'private gameplay'
Put-SnapshotFile 'nvngx_dlssnr.dll' 'runtime must not be included'
Put-SnapshotFile 'captures/dogfood/base/neural_dogfood.cfg' 'stale launch commands'
$before = @(Get-ChildItem -LiteralPath $root -File -Recurse | Get-FileHash)
$result = Save-NeuralSettingsSnapshot -RepoRoot $root -Destination (Join-Path $fixture 'settings.zip')
$files = Read-SnapshotZip $result.Path
if ($result.FileCount -ne 5 -or $files.Count -ne 6 -or $result.Warnings.Count -ne 0) { throw 'Snapshot inventory differs from the settings allowlist.' }
$manifest = [Text.Encoding]::UTF8.GetString($files['snapshot.json']) | ConvertFrom-Json
$hash = [Security.Cryptography.SHA256]::Create()
try {
    foreach ($record in $manifest.files) {
        if ([BitConverter]::ToString($hash.ComputeHash($files[$record.path])).Replace('-', '') -ne $record.sha256 -or $files[$record.path].Length -ne $record.bytes) { throw 'ZIP content differs from its checksum manifest.' }
    }
} finally { $hash.Dispose() }
if ([Text.Encoding]::UTF8.GetString($files['active-preset/reshade-preset.ini']) -ne "[Fake.fx]`nStrength=0.25") { throw 'Active effects preset not captured.' }
foreach ($item in $before) { if ((Get-FileHash -LiteralPath $item.Path).Hash -ne $item.Hash) { throw 'Snapshot modified source settings/progress/runtime.' } }
$originalZip = (Get-FileHash -LiteralPath $result.Path).Hash
$caught = $false
try { Save-NeuralSettingsSnapshot -RepoRoot $root -Destination $result.Path | Out-Null } catch { $caught = $_.Exception.Message -like '*already exists*' }
if (-not $caught -or (Get-FileHash -LiteralPath $result.Path).Hash -ne $originalZip) { throw 'Existing snapshot overwritten.' }

$mutex = & $script:snapshotGuard -Name $script:snapshotMutex
try { Expect-SnapshotFailure 'busy' '*Close Doom 3*' } finally { $mutex.Dispose() }
Put-SnapshotFile 'captures/dogfood/base/neural_settings_reset.pending' 'version1'
Expect-SnapshotFailure 'pending' '*Finish the pending reset*'
Remove-Item -LiteralPath (Join-Path $root 'captures/dogfood/base/neural_settings_reset.pending')
$locked = [IO.File]::Open((Join-Path $root 'reshade.ini'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try { Expect-SnapshotFailure 'locked' '*used by another process*' } finally { $locked.Dispose() }

Put-SnapshotFile 'reshade.ini' "[GENERAL]`nPresetPath=missing.ini`n[RenoDX.DLSS5]`nNeuralUplift=1"
$missing = Save-NeuralSettingsSnapshot -RepoRoot $root -Destination (Join-Path $fixture 'missing-default-preset.zip')
if ($missing.Warnings.Count -ne 1 -or (Read-SnapshotZip $missing.Path).ContainsKey('active-preset/reshade-preset.ini')) { throw 'Missing optional preset was silently claimed as captured.' }
$external = Join-Path $fixture 'outside.ini'; [IO.File]::WriteAllText($external, '[External.fx]')
Put-SnapshotFile 'reshade.ini' ("[GENERAL]`nPresetPath=" + $external)
$externalResult = Save-NeuralSettingsSnapshot -RepoRoot $root -Destination (Join-Path $fixture 'external-preset.zip')
if ([Text.Encoding]::UTF8.GetString((Read-SnapshotZip $externalResult.Path)['active-preset/reshade-preset.ini']) -ne '[External.fx]') { throw 'Explicit external preset was not captured.' }

$linkedRoot = Join-Path $fixture 'linked-install'
New-Item -ItemType Directory -Path (Join-Path $linkedRoot 'base') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $linkedRoot 'base/default.cfg'), 'shipped')
New-Item -ItemType Junction -Path (Join-Path $linkedRoot 'captures') -Target (Join-Path $root 'captures') | Out-Null
$originalRoot = $root; $root = $linkedRoot
try { Expect-SnapshotFailure 'linked' '*linked paths*' } finally { $root = $originalRoot }
if (Get-ChildItem -LiteralPath $fixture -Filter '.neuraldoom-snapshot-*.tmp' -Recurse) { throw 'Temporary snapshot archive leaked.' }
Write-Host 'PASS: exact settings ZIP/checksums, external/missing presets, exclusion of progress/runtime/launch commands, no overwrite, mutex/pending/locked/link rejection; source files unchanged. No game launched.'
