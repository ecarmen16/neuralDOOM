[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Reset-NeuralSettings.ps1')
$fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('../../captures/neural/settings-reset-' + [guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
# Use the real named-mutex guard with a private name: never interfere with a
# player's running DOOM3 mutex, and never invoke a real game or reset a live root.
$script:resetGuard = ${function:New-NeuralSettingsResetGuard}
$script:resetTestMutex = 'neuralDoom-settings-test-' + [guid]::NewGuid().ToString('N')
function New-NeuralSettingsResetGuard { & $script:resetGuard -Name $script:resetTestMutex }

function Put-ResetFixture([string]$Root, [string]$Name, [string]$Text) {
    $path = Join-Path $Root $Name
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $Text)
}
function Get-ResetFixtureHashes([string]$Root) {
    $hashes = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File) {
        $relative = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
        if ($relative -notlike '.neuraldoom-cache/*') { $hashes[$relative] = (Get-FileHash -LiteralPath $file.FullName).Hash }
    }
    return $hashes
}
function Assert-ResetFixtureHashes([string]$Root, [hashtable]$Expected) {
    $actual = Get-ResetFixtureHashes $Root
    if ($actual.Count -ne $Expected.Count) { throw 'Reset failure changed the file inventory.' }
    foreach ($name in $Expected.Keys) { if ($actual[$name] -ne $Expected[$name]) { throw "Unexpected settings mutation: $name" } }
}
function New-ResetFixture([string]$Name) {
    $root = Join-Path $fixture $Name
    Put-ResetFixture $root 'base/default.cfg' 'shipped default controls'
    Put-ResetFixture $root 'base/neural_rtx_contrast.cfg' 'shipped contrast defaults'
    Put-ResetFixture $root 'base/D3BFGConfig.cfg' "set g_roeNightmare 1`r`nset r_hdrOutput 1"
    Put-ResetFixture $root 'captures/dogfood/base/D3BFGConfig.cfg' "set g_nightmare `"1`"`r`nset g_leNightmare 1`r`nset r_neuralReconstructionMode 4`r`nset s_volume_dB -12`r`nbind F1 customCommand"
    Put-ResetFixture $root 'base/autoexec.cfg' 'set r_hdrFixedLuminance 8'
    Put-ResetFixture $root 'captures/dogfood/base/autoexec.cfg' 'set r_hdrFixedLuminance 9'
    Put-ResetFixture $root 'captures/dogfood/base/default.cfg' 'custom default shadow'
    Put-ResetFixture $root 'captures/dogfood/base/neural_dogfood.cfg' 'stale launch choices'
    Put-ResetFixture $root 'captures/dogfood/installed-profile.pending' 'NR'
    Put-ResetFixture $root 'captures/dogfood/settings-doom-contrast-v1.applied' 'old marker'
    Put-ResetFixture $root 'captures/dogfood/base/savegame/profile.bin' 'opaque profile with stats and achievements; must remain byte-identical'
    Put-ResetFixture $root 'captures/dogfood/base/savegame/GAME-quick/savegame.dat' 'precious campaign save'
    Put-ResetFixture $root 'base/savegame/profile.bin' 'fallback profile progress'
    Put-ResetFixture $root 'captures/dogfood/base/screenshots/keep.png' 'precious screenshot'
    Put-ResetFixture $root 'personal.cfg' 'unrelated personal file'
    Put-ResetFixture $root 'reshade.ini' "[GENERAL]`r`nPresetPath=$(Join-Path $fixture 'external.ini')`r`n[RenoDX.DLSS5]`r`nNRIntensity=12`r`nNREnableUpscaling=1"
    Put-ResetFixture $root 'ReShadePreset.ini' 'custom local effect preset'
    Put-ResetFixture $root 'imgui.ini' 'custom overlay layout'
    return $root
}

Put-ResetFixture $fixture 'external.ini' 'external preset must remain untouched'
$install = New-ResetFixture 'complete'
$before = Get-ResetFixtureHashes $install
$backup = Reset-NeuralGameSettings -RepoRoot $install
$journal = Get-Content -LiteralPath (Join-Path $backup 'reset.json') -Raw | ConvertFrom-Json
if ($journal.status -ne 'complete') { throw 'Reset did not complete.' }
foreach ($record in $journal.files) {
    $copy = Join-Path $backup $record.path
    if ((Get-FileHash -LiteralPath $copy).Hash -ne $before[$record.path] -or $record.sha256 -ne $before[$record.path]) { throw 'Backup is not byte-exact.' }
}
foreach ($name in @('captures/dogfood/base/savegame/profile.bin', 'base/savegame/profile.bin', 'captures/dogfood/base/savegame/GAME-quick/savegame.dat', 'captures/dogfood/base/screenshots/keep.png', 'base/default.cfg', 'base/neural_rtx_contrast.cfg', 'personal.cfg')) {
    if ((Get-FileHash -LiteralPath (Join-Path $install $name)).Hash -ne $before[$name]) { throw "Reset changed progress, saves or shipped files: $name" }
}
$config = Get-Content -LiteralPath (Join-Path $install 'captures/dogfood/base/D3BFGConfig.cfg') -Raw
foreach ($name in @('g_nightmare', 'g_roeNightmare', 'g_leNightmare')) { if ($config -notmatch ('set ' + $name + ' "1"')) { throw 'Campaign unlock was lost.' } }
if ($config -match 'r_neuralReconstructionMode|s_volume|bind ') { throw 'Old preferences survived the reset.' }
foreach ($name in @('base/D3BFGConfig.cfg', 'base/autoexec.cfg', 'captures/dogfood/base/autoexec.cfg', 'captures/dogfood/base/default.cfg', 'captures/dogfood/base/neural_dogfood.cfg', 'captures/dogfood/installed-profile.pending', 'captures/dogfood/settings-doom-contrast-v1.applied', 'ReShadePreset.ini', 'imgui.ini')) {
    if (Test-Path -LiteralPath (Join-Path $install $name)) { throw "Old settings remain active: $name" }
}
if ([IO.File]::ReadAllText((Join-Path $install 'captures/dogfood/base/neural_settings_reset.pending')) -ne "version1`r`n") { throw 'Missing engine profile-reset request.' }
. (Join-Path $PSScriptRoot 'EmbeddedNR.ps1')
$seed = "[INPUT]`r`nKeyOverlay=36,0,0,0`r`nKeyEffects=0,0,0,0`r`n[RenoDX.DLSS5]`r`n"
if ([IO.File]::ReadAllText((Join-Path $install 'reshade.ini')) -cne (Get-NeuralNRFullResolutionConfig -Text $seed)) { throw 'NR settings differ from the shipped installer seed.' }
if ([IO.File]::ReadAllText((Join-Path $fixture 'external.ini')) -ne 'external preset must remain untouched') { throw 'Reset followed an external preset path.' }
$secondBackup = Reset-NeuralGameSettings -RepoRoot $install
if ($secondBackup -eq $backup -or -not (Test-Path -LiteralPath (Join-Path $backup 'reset.json'))) { throw 'Retry overwrote the previous backup.' }
Write-Host 'PASS: full preference reset, exact backups, NR installer defaults, preserved saves/profile bytes/unlocks, detached external preset and repeated reset.'

$rollback = New-ResetFixture 'rollback'
$before = Get-ResetFixtureHashes $rollback
$lock = [IO.File]::Open((Join-Path $rollback 'base/autoexec.cfg'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
$caught = $false
try { try { Reset-NeuralGameSettings -RepoRoot $rollback | Out-Null } catch { $caught = $true } }
finally { $lock.Dispose() }
if (-not $caught) { throw 'Locked settings were accepted.' }
Assert-ResetFixtureHashes $rollback $before
$journals = @(Get-ChildItem -LiteralPath (Join-Path $rollback '.neuraldoom-cache/settings-reset') -Filter reset.json -Recurse -File)
if ($journals.Count -ne 1 -or (Get-Content -LiteralPath $journals[0].FullName -Raw | ConvertFrom-Json).status -ne 'restored-after-failure') { throw 'Failed reset did not record rollback.' }
Reset-NeuralGameSettings -RepoRoot $rollback | Out-Null
Write-Host 'PASS: a mid-transaction sharing violation restores earlier files exactly; retry succeeds.'

$busy = New-ResetFixture 'busy'
$before = Get-ResetFixtureHashes $busy
$mutex = & $script:resetGuard -Name $script:resetTestMutex
$caught = $false
try { try { Reset-NeuralGameSettings -RepoRoot $busy | Out-Null } catch { $caught = $_.Exception.Message -match 'Close Doom 3' } }
finally { $mutex.Dispose() }
if (-not $caught) { throw 'Existing game mutex was ignored.' }
Assert-ResetFixtureHashes $busy $before
if (Test-Path -LiteralPath (Join-Path $busy '.neuraldoom-cache')) { throw 'Busy rejection created a backup.' }

$linked = Join-Path $fixture 'linked'
Put-ResetFixture $linked 'base/default.cfg' 'shipped defaults'
New-Item -ItemType Directory -Path (Join-Path $linked 'captures') -Force | Out-Null
$external = Join-Path $fixture 'linked-target'
Put-ResetFixture $external 'base/D3BFGConfig.cfg' 'leave linked settings untouched'
New-Item -ItemType Junction -Path (Join-Path $linked 'captures/dogfood') -Target $external | Out-Null
$caught = $false
try { Reset-NeuralGameSettings -RepoRoot $linked | Out-Null } catch { $caught = $_.Exception.Message -match 'linked paths' }
if (-not $caught -or [IO.File]::ReadAllText((Join-Path $external 'base/D3BFGConfig.cfg')) -ne 'leave linked settings untouched') { throw 'Linked settings were followed.' }
foreach ($relative in @('../escape', 'C:/escape', 'x:stream', 'dir/../../escape')) {
    $caught = $false
    try { Get-NeuralSettingsResetPath $install $relative | Out-Null } catch { $caught = $true }
    if (-not $caught) { throw 'Unsafe path accepted.' }
}
$native = Join-Path $fixture 'native-empty'
Put-ResetFixture $native 'base/default.cfg' 'shipped defaults'
Reset-NeuralGameSettings -RepoRoot $native | Out-Null
if (Test-Path -LiteralPath (Join-Path $native 'reshade.ini')) { throw 'Native-only reset installed an NR configuration.' }
Write-Host 'PASS: mutex exclusion, path and junction rejection, and empty native installation. No game launched.'
Write-Host "Fixtures: $fixture"
