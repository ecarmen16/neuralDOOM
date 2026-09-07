[CmdletBinding()]
param(
    [string]$RepoRoot,
    [ValidateSet('Native', 'DLAA', 'NR')][string]$Profile,
    [string]$BuildDirectory,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo',
    [switch]$ValidateOnly,
    [switch]$PrepareOnly,
    [switch]$RayTracedAO,
    [switch]$RayTracedContactShadows,
    [switch]$RayTracedGI,
    [switch]$RayTracedReflections,
    [ValidateSet('Saved', 'SDR', 'AutoHDR')][string]$DisplayOutput = 'Saved'
)

. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'EmbeddedNR.ps1')
if ($ValidateOnly -and $PrepareOnly) { throw 'Choose either -ValidateOnly or -PrepareOnly.' }
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
if (-not $Profile) {
    if ($ValidateOnly) { throw '-ValidateOnly requires -Profile Native, DLAA or NR.' }
    Write-Host 'neuralDoom playtest'
    Write-Host '1. Native rendering'
    Write-Host '2. Native DLAA'
    Write-Host '3. NR toggle on F6 (existing engine-loaded compatibility stack)'
    $selection = Read-Host 'Choose 1, 2 or 3 (Enter = Native)'
    switch ($selection) {
        '' { $Profile = 'Native' }
        '1' { $Profile = 'Native' }
        '2' { $Profile = 'DLAA' }
        '3' { $Profile = 'NR' }
        default { throw 'Choose 1, 2 or 3.' }
    }
}
if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $RepoRoot $(if ($Profile -ne 'Native') { 'build-streamline' } else { 'build-rt' })
}
$BuildDirectory = Resolve-NeuralFullPath $BuildDirectory
$exe = Find-NeuralDoomExecutable -RepoRoot $RepoRoot -BuildDirectory $BuildDirectory -Configuration $Configuration
if (-not $exe) { throw 'The configured executable is missing. Build before playtesting.' }
$manifestPath = Join-Path $BuildDirectory "neuraldoom-build-$Configuration.json"
if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Run Build-RBDOOM.ps1 to record the executable identity first.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.sha256 -ne (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -or
    $manifest.executable -ne $exe -or $manifest.configuration -ne $Configuration) {
    throw 'The executable does not match its build manifest. Rebuild before playtesting.'
}
if ($manifest.features.dx12 -ne 'ON' -or $manifest.features.rayTracing -ne 'ON') {
    throw 'This checklist requires a DX12 build configured with -RayTracing ON.'
}
foreach ($shader in @('ray_query', 'ambient_occlusion', 'contact_shadows', 'visibility_debug', 'material_atlas', 'diffuse_bounce', 'bounce_composite', 'reflections', 'reflection_filter', 'reflection_composite')) {
    $shaderPath = Join-Path $RepoRoot "base/renderprogs2/dxil/rt/$shader.cs.dxil"
    if (-not (Test-Path -LiteralPath $shaderPath -PathType Leaf) -or (Get-Item -LiteralPath $shaderPath).Length -eq 0) {
        throw "Missing RTX shader: $shader. Rebuild before playtesting."
    }
}
Assert-NeuralShaderManifest -RepoRoot $RepoRoot -Manifest $manifest
if ($Profile -ne 'Native') {
    if ($manifest.features.streamline -ne 'ON') { throw "$Profile requires the existing official Streamline build." }
    foreach ($dll in @('sl.interposer.dll', 'sl.common.dll', 'sl.dlss.dll', 'nvngx_dlss.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path (Split-Path $exe) $dll))) { throw "Missing SDK component: $dll" }
    }
}
$nrState = $null
if ($Profile -eq 'NR') { $nrState = Get-NeuralEmbeddedNRState -RepoRoot $RepoRoot -BuildExecutable $exe }
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'base/maps/mars_city2.resources'))) {
    throw 'Run this launcher from the game checkout containing your local BFG data.'
}
$saveRoot = Join-Path $RepoRoot 'captures/dogfood'
$saveBase = Join-Path $saveRoot 'base'
$firstRun = -not (Test-Path -LiteralPath (Join-Path $saveBase 'D3BFGConfig.cfg'))
$backend = if ($Profile -ne 'Native') { 2 } else { 0 }
$sdk = if ($Profile -ne 'Native') { 1 } else { 0 }
$launchArgs = @(
    '+set', 'fs_basepath', ('"' + $RepoRoot + '"'), '+set', 'fs_savepath', ('"' + $saveRoot + '"'),
    '+set', 'r_graphicsAPI', 'dx12', '+set', 'r_neuralCompatibilityEnable', $(if ($Profile -eq 'NR') { '1' } else { '0' }),
    '+set', 'r_streamlineEnable', $sdk, '+set', 'r_streamlineApplicationId', '0',
    '+set', 'r_neuralBackend', $backend, '+set', 'com_allowConsole', '1',
    '+set', 'logFileName', "dogfood-$Profile.log", '+set', 'logFile', '2',
    '+exec', 'neural_dogfood.cfg'
)
if ($RayTracedAO) {
    $launchArgs += @('+set', 'r_rayTracedAO', '1', '+set', 'r_useSSAO', '1', '+set', 'r_useNewSSAOPass', '1')
}
if ($RayTracedContactShadows) { $launchArgs += @('+set', 'r_rayTracedContactShadows', '1') }
if ($RayTracedGI) { $launchArgs += @('+set', 'r_rayTracedGI', '1') }
if ($RayTracedReflections) { $launchArgs += @('+set', 'r_rayTracedReflections', '1') }
# Seed display settings once. Later HUD, resolution and HDR edits must survive relaunch.
if ($firstRun) {
    $launchArgs += @('+set', 'r_fullscreen', '0', '+set', 'r_windowWidth', '2560',
        '+set', 'r_windowHeight', '720')
}
if ($firstRun -or $DisplayOutput -ne 'Saved') {
    $launchArgs += @('+set', 'r_hdrOutput', $(if ($DisplayOutput -eq 'AutoHDR') { 1 } else { 0 }))
}
if ([Text.Encoding]::UTF8.GetByteCount(($launchArgs -join ' ')) -ge 1024) {
    throw 'Launch arguments exceed the engine limit; use a shorter checkout path.'
}
Write-Host "Profile:    $Profile"
if ($RayTracedAO) { Write-Host 'RTX AO:     Enabled (static world). Toggle live with r_rayTracedAO 0 / 1.' }
if ($RayTracedContactShadows) { Write-Host 'RTX contact shadows: Enabled. Toggle with r_rayTracedContactShadows 0 / 1.' }
if ($RayTracedReflections) { Write-Host 'RTX reflections: Enabled at full resolution. Toggle with r_rayTracedReflections 0 / 1.' }
if ($RayTracedGI) { Write-Host 'RTX material bounce: Enabled. Toggle with r_rayTracedGI 0 / 1; strength: r_rayTracedGIStrength.' }
Write-Host 'Optional keybinds: exec neural_rtx_keys.cfg (F4 GI, F6 NR, F7 AO, F8 contacts, F9 reflections, F10 views, F11 all).'
if ($Profile -eq 'NR') {
    Write-Host 'NR: F6 toggles the installed add-on; F4 toggles bounce. Full-resolution DLAA passthrough when NR is off.'
    Write-Host 'NR uses engine-loaded compatibility components without a dxgi.dll proxy. Native HDR is bypassed in this profile.'
    Write-Host "NR launch stages the verified engine at: $($nrState.executable)"
}
Write-Host "Executable: $exe"
Write-Host "Commit:     $($manifest.commit) (dirty=$($manifest.dirty))"
Write-Host "Settings:   $saveRoot"
Write-Host "Display:    $DisplayOutput"
Write-Host 'Checklist:  docs/neural-rendering/DOGFOOD_CHECKLIST.md'
if ($ValidateOnly) {
    Write-Host 'PASS: exact executable, manifest, feature flags, runtime files and local map data. No game started.'
    return
}
$existingGame = $null
try { $existingGame = [Threading.Mutex]::OpenExisting('DOOM3') }
catch [Threading.WaitHandleCannotBeOpenedException] { }
if ($null -ne $existingGame) {
    $existingGame.Dispose()
    throw 'Another Doom 3 instance is running. Close it before starting this playtest.'
}
New-Item -ItemType Directory -Path $saveBase -Force | Out-Null
$playtestCommands = @(
    'set r_screenFraction 100', 'set r_renderMode 0', 'set r_useTemporalAA 1', 'set r_antiAliasing 2',
    'set com_fixedTic 0', 'set s_noSound 0', 'set r_hdrDiagnostic 0',
    'neuralBackendStatus', 'hdrStatus', 'rayTracingStatus'
)
# Versioned migration: apply in the game after its saved config has loaded.
# Only acknowledge it after a successful session, so preparation/crashes retry.
$settingsMigrationMarker = Join-Path $saveRoot 'settings-doom-contrast-v1.applied'
$settingsMigrationPending = -not (Test-Path -LiteralPath $settingsMigrationMarker)
if ($settingsMigrationPending) {
    $oldConfig = Join-Path $saveBase 'D3BFGConfig.cfg'
    $backup = Join-Path $saveRoot 'settings-before-doom-contrast-v1.cfg'
    if ((Test-Path -LiteralPath $oldConfig) -and -not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $oldConfig -Destination $backup
    }
    $preset = Join-Path $PSScriptRoot '../../base/neural_rtx_contrast.cfg'
    $playtestCommands += @(Get-Content -LiteralPath $preset -ErrorAction Stop)
    Write-Host 'Applying updated Doom contrast defaults once; HDR calibration and rendering quality are preserved.'
}
if ($Profile -eq 'NR') {
    $exe = Initialize-NeuralEmbeddedNRLaunch -RepoRoot $RepoRoot -BuildExecutable $exe -ExpectedHash $manifest.sha256 -SaveBase $saveBase
    # The add-on reads F6 directly. Remove the previous engine bounce binding
    # so one key press cannot also change ray lighting during the comparison.
    $playtestCommands += @('unbind F6', 'bind F4 "toggle r_rayTracedGI; neuralHistoryReset"', 'neuralCompatibilityStatus')
}
$playtestCommands | Set-Content -LiteralPath (Join-Path $saveBase 'neural_dogfood.cfg') -Encoding ASCII
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $saveRoot "build-$Profile.json") -Encoding UTF8
if ($PrepareOnly) {
    Write-Host 'PREPARED: playtest settings and selected executable are ready. No game started.'
    return
}
# Interactive launch explicitly requested by the person running this helper.
$process = Start-Process -FilePath $exe -ArgumentList $launchArgs -WorkingDirectory $RepoRoot -WindowStyle Normal -PassThru
$process.WaitForExit()
$process.Refresh()
if ($process.ExitCode -ne 0) { throw "Game exited with code $($process.ExitCode). See $saveBase/dogfood-$Profile.log" }

if ($settingsMigrationPending) {
    'Applied after successful game exit.' | Set-Content -LiteralPath $settingsMigrationMarker -Encoding ASCII
}
