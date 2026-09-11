[CmdletBinding()]
param(
    [string]$RepoRoot,
    [ValidateSet('Native', 'DLAA', 'NR')][string]$Profile,
    [string]$BuildDirectory,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo',
    [switch]$ValidateOnly,
    [switch]$PrepareOnly,
    [switch]$NoLauncher,
    [ValidateSet('TAA', 'DLAA', 'Quality', 'Balanced', 'Performance')][string]$Reconstruction,
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
$showLauncher = -not $Profile -and -not $ValidateOnly -and -not $PrepareOnly -and -not $NoLauncher
$selectedReconstruction = if ($Reconstruction) { [array]::IndexOf(@('TAA','DLAA','Quality','Balanced','Performance'), $Reconstruction) } else { $null }
$askAtLaunch = $false
$pendingProfile = Join-Path $RepoRoot 'captures/dogfood/installed-profile.pending'
if (-not $Profile -and (Test-Path -LiteralPath $pendingProfile)) {
    $selectedProfile = (Get-Content -LiteralPath $pendingProfile -Raw).Trim()
    if ($selectedProfile -in @('Native','DLAA','NR')) { $Profile = $selectedProfile }
}
# Resolve the menu preference before offering startup-only profile choices.
$profileConfig = Join-Path $RepoRoot 'captures/dogfood/base/D3BFGConfig.cfg'
if (-not $Profile -and (Test-Path -LiteralPath $profileConfig)) {
    $profileText = Get-Content -LiteralPath $profileConfig -Raw
    if ($profileText -match '(?m)^set\s+r_neuralLaunchProfile\s+"?(-1|[012])"?\s*$') {
        $askAtLaunch = [int]$Matches[1] -eq -1
        if (-not $askAtLaunch) { $Profile = @('Native', 'DLAA', 'NR')[[int]$Matches[1]] }
    }
}
if (-not $Profile -and -not $askAtLaunch -and (Test-Path -LiteralPath (Join-Path $RepoRoot '.neuraldoom-install.json'))) {
    $installed = Get-Content -LiteralPath (Join-Path $RepoRoot '.neuraldoom-install.json') -Raw | ConvertFrom-Json
    if ($installed.profile -in @('Native', 'DLAA', 'NR')) { $Profile = $installed.profile }
}
if ($showLauncher) {
    . (Join-Path $PSScriptRoot 'LaunchPicker.ps1')
    $preferredMode = 1
    $preferredNRMode = 1
    if (Test-Path -LiteralPath $profileConfig) {
        $profileText = Get-Content -LiteralPath $profileConfig -Raw
        if ($profileText -match '(?m)^set\s+r_neuralReconstructionMode\s+"?([0-4])"?\s*$') { $preferredMode = [int]$Matches[1] }
        if ($profileText -match '(?m)^set\s+r_neuralNRReconstructionMode\s+"?([1-4])"?\s*$') { $preferredNRMode = [int]$Matches[1] }
    }
    if ($null -ne $selectedReconstruction) {
        if ($Profile -eq 'NR') { $preferredNRMode = $selectedReconstruction }
        else { $preferredMode = $selectedReconstruction }
    }
    $choice = Show-NeuralLaunchPicker -RepoRoot $RepoRoot -BuildDirectory $BuildDirectory -Configuration $Configuration -PreferredProfile $Profile -PreferredMode $preferredMode -PreferredNRMode $preferredNRMode
    if ($null -eq $choice) { return }
    $Profile = $choice.Profile
    $selectedReconstruction = if ($Profile -ne 'Native') { $choice.Mode } else { $null }
    $askAtLaunch = $false
}
if (-not $Profile) {
    if ($ValidateOnly) { throw '-ValidateOnly requires -Profile Native, DLAA or NR.' }
    Write-Host 'neuralDoom'
    Write-Host '1. Native rendering'
    Write-Host '2. DLAA / DLSS'
    Write-Host '3. Neural Rendering (F6 toggle)'
    $selection = Read-Host 'Choose 1, 2 or 3 (Enter = Native)'
    switch ($selection) {
        '' { $Profile = 'Native' }
        '1' { $Profile = 'Native' }
        '2' { $Profile = 'DLAA' }
        '3' { $Profile = 'NR' }
        default { throw 'Choose 1, 2 or 3.' }
    }
}
if ($null -ne $selectedReconstruction -and $Profile -eq 'Native') { throw '-Reconstruction requires the DLAA / DLSS or NR profile.' }
if ($Profile -eq 'NR' -and $null -ne $selectedReconstruction -and $selectedReconstruction -eq 0) { throw 'NR requires a DLAA or DLSS evaluation; TAA is only available in the DLAA / DLSS profile.' }
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
    throw 'This launcher requires a DX12 build configured with -RayTracing ON.'
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
    throw 'Doom 3 BFG data is missing. Rerun setup and select your installed BFG game folder.'
}
$saveRoot = Join-Path $RepoRoot 'captures/dogfood'
$saveBase = Join-Path $saveRoot 'base'
$firstRun = (Test-Path -LiteralPath (Join-Path $saveBase 'neural_settings_reset.pending')) -or
    -not (Test-Path -LiteralPath (Join-Path $saveBase 'D3BFGConfig.cfg'))
[string]$savedConfig = if ($firstRun) { '' } else { Get-Content -LiteralPath (Join-Path $saveBase 'D3BFGConfig.cfg') -Raw }
$backend = if ($Profile -ne 'Native') { 2 } else { 0 }
$quality = 0
# A pre-existing SDK preset must not silently reduce a new NR profile's resolution.
$reconstructionCvar = if ($Profile -eq 'NR') { 'r_neuralNRReconstructionMode' } else { 'r_neuralReconstructionMode' }
if ($Profile -ne 'Native' -and -not $firstRun) {
    $modeRange = if ($Profile -eq 'NR') { '[1-4]' } else { '[0-4]' }
    if ($savedConfig -match ('(?m)^set\s+' + $reconstructionCvar + '\s+"?(' + $modeRange + ')"?\s*$')) {
        $mode = [int]$Matches[1]
        if ($mode -eq 0) { $backend = 0 }
        elseif ($mode -ge 2) { $backend = 3; $quality = $mode - 2 }
    }
}
if ($null -ne $selectedReconstruction) {
    $backend = if ($selectedReconstruction -eq 0) { 0 } elseif ($selectedReconstruction -eq 1) { 2 } else { 3 }
    $quality = [Math]::Max(0, $selectedReconstruction - 2)
}
$sessionLog = "dogfood-$Profile-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.log'
$sdk = if ($Profile -ne 'Native') { 1 } else { 0 }
$launchArgs = @(
    '+set', 'fs_basepath', ('"' + $RepoRoot + '"'), '+set', 'fs_savepath', ('"' + $saveRoot + '"'),
    '+set', 'r_graphicsAPI', 'dx12', '+set', 'r_neuralCompatibilityEnable', $(if ($Profile -eq 'NR') { '1' } else { '0' }),
    '+set', 'r_streamlineEnable', $sdk, '+set', 'r_streamlineApplicationId', '0',
    '+set', 'r_neuralBackend', $backend, '+set', 'com_allowConsole', '1',
    '+set', 'logFileName', $sessionLog, '+set', 'logFile', '2',
    '+exec', 'neural_dogfood.cfg'
)
# Profile switches seed missing preferences; menu choices survive later launches.
foreach ($feature in @(
    @{ requested = $RayTracedAO; cvar = 'r_rayTracedAO' },
    @{ requested = $RayTracedContactShadows; cvar = 'r_rayTracedContactShadows' },
    @{ requested = $RayTracedGI; cvar = 'r_rayTracedGI' },
    @{ requested = $RayTracedReflections; cvar = 'r_rayTracedReflections' }
)) {
    if ($feature.requested -and $savedConfig -notmatch ('(?m)^set\s+' + $feature.cvar + '\s+')) {
        $launchArgs += @('+set', $feature.cvar, '1')
        if ($feature.cvar -eq 'r_rayTracedAO') { $launchArgs += @('+set', 'r_useSSAO', '1', '+set', 'r_useNewSSAOPass', '1') }
    }
}
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
Write-Host "Reconstruction: $(if ($backend -eq 2) { 'DLAA' } elseif ($backend -eq 3) { 'DLSS ' + @('Quality','Balanced','Performance')[$quality] } else { 'Native TAA' })"
Write-Host 'Rendering controls: System Settings. Remap toggles in Keyboard Bindings; console: ~.'
if ($Profile -eq 'NR') {
    Write-Host 'F6: NR on/off, retaining the selected DLAA/DLSS reconstruction. Native HDR is unavailable in this profile.'
    if ($backend -eq 3) { Write-Host 'Experimental: NR + DLSS still requires branch runtime validation.' }
    Write-Verbose "NR executable: $($nrState.executable)"
}
Write-Host "Log: captures/dogfood/base/$sessionLog"
Write-Verbose "Executable: $exe; commit: $($manifest.commit); dirty: $($manifest.dirty)"
Write-Verbose "Settings: $saveRoot; display: $DisplayOutput"
if ($ValidateOnly) {
    Write-Host 'PASS: installation validated.'
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
# Probe the actual target before starting the engine. Never truncate a previous
# session log or fail because it is read-only/open in another application.
try {
    $probe = [IO.File]::Open((Join-Path $saveBase $sessionLog), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $probe.Dispose()
} catch { throw "Cannot write saves/logs in $saveBase. Choose a writable installation folder. $($_.Exception.Message)" }
$playtestCommands = @(
    ('set r_neuralLaunchProfile ' + $(if ($askAtLaunch) { -1 } else { [array]::IndexOf(@('Native', 'DLAA', 'NR'), $Profile) })),
    ('set r_neuralDLSSQuality ' + $quality),
    'set r_screenFraction 100', 'set r_renderMode 0', 'set r_useTemporalAA 1', 'set r_antiAliasing 2',
    'neuralInstallKeys startup', 'set com_fixedTic 0', 'set s_noSound 0', 'set r_hdrDiagnostic 0'
)
if ($Profile -ne 'Native') {
    $effectiveMode = if ($backend -eq 0) { 0 } elseif ($backend -eq 2) { 1 } else { $quality + 2 }
    $playtestCommands += 'set ' + $reconstructionCvar + ' ' + $effectiveMode
    # Match in-game mode changes: DLAA enables moving geometry; upscaled DLSS
    # starts with it off while dynamic reflection history is investigated.
    if ($backend -ne 0) { $playtestCommands += 'set r_rayTracingDynamicGeometry ' + $(if ($backend -eq 2) { 1 } else { 0 }) }
}
if ($VerbosePreference -ne 'SilentlyContinue') { $playtestCommands += @('neuralBackendStatus', 'hdrStatus', 'rayTracingStatus') }
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
    Write-Host 'Applying updated Doom contrast defaults.'
}
if ($Profile -eq 'NR') {
    $exe = Initialize-NeuralEmbeddedNRLaunch -RepoRoot $RepoRoot -BuildExecutable $exe -ExpectedHash $manifest.sha256 -SaveBase $saveBase
    if ($VerbosePreference -ne 'SilentlyContinue') { $playtestCommands += 'neuralCompatibilityStatus' }
}
$playtestCommands | Set-Content -LiteralPath (Join-Path $saveBase 'neural_dogfood.cfg') -Encoding ASCII
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $saveRoot "build-$Profile.json") -Encoding UTF8
if ($PrepareOnly) {
    Write-Host 'PREPARED: ready to launch.'
    return
}
# Interactive launch explicitly requested by the person running this helper.
$process = Start-Process -FilePath $exe -ArgumentList $launchArgs -WorkingDirectory $RepoRoot -WindowStyle Normal -PassThru
$process.WaitForExit()
$process.Refresh()
if ($process.ExitCode -ne 0) { throw "Game exited with code $($process.ExitCode). See $saveBase/$sessionLog" }
if (Test-Path -LiteralPath $pendingProfile) { Remove-Item -LiteralPath $pendingProfile }

if ($settingsMigrationPending) {
    'Applied after successful game exit.' | Set-Content -LiteralPath $settingsMigrationMarker -Encoding ASCII
}
