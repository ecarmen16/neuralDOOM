[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$BuildDirectory,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo',
    [ValidateSet('Native', 'Validate', 'DLAA')][string]$Profile = 'Native',
    [switch]$DLSSPresetMatrix,
    [ValidateRange(640, 7680)][int]$Width = 1280,
    [ValidateRange(360, 4320)][int]$Height = 720,
    [switch]$Borderless,
    [ValidateRange(60, 100)][int]$FieldOfView = 80,
    [ValidateRange(0.5, 1.5)][float]$HudScale = 1,
    [ValidateRange(0, 4)][float]$HudMaxAspect = 0,
    [ValidateSet('SDR', 'AutoHDR')][string]$DisplayOutput = 'SDR',
    [ValidateSet('Either', 'Active', 'SDR')][string]$ExpectedHDR = 'Either',
    [switch]$HDRDiagnostic,
    [ValidateRange(0, 7680)][int]$ResizeWidth = 0,
    [ValidateRange(0, 4320)][int]$ResizeHeight = 0,
    [ValidateRange(0, 1)][int]$LegacyRenderMode = 0,
    [ValidateRange(60, 3600)][int]$Frames = 120,
    [ValidateRange(30, 600)][int]$TimeoutSeconds = 120,
    [switch]$GpuProfile,
    [ValidateSet('Baseline', 'NoSSAO', 'NoSSR', 'Shadow4')][string]$LightingVariant = 'Baseline',
    [ValidateRange(180, 3600)][int]$WarmupFrames = 180,
    [ValidateSet('Any', 'Local', 'Fallback')][string]$ExpectedProbeLighting = 'Any',
    [ValidateSet('None', 'BuildDisabled', 'Synthetic', 'Scene', 'MissingShader')][string]$RayTracingDiagnostics = 'None',
    [ValidateRange(0, 2)][int]$ValidationLayers = 1,
    [switch]$RayTracedAO,
    [switch]$RayTracedContactShadows,
    [switch]$RayTracedGI,
    [switch]$RayTracedReflections,
    [switch]$RayTracingDebugViews,
    [switch]$PassThru
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) { $BuildDirectory = Join-Path $RepoRoot 'build' }
$BuildDirectory = Resolve-NeuralFullPath $BuildDirectory
$exe = Find-NeuralDoomExecutable -RepoRoot $RepoRoot -BuildDirectory $BuildDirectory -Configuration $Configuration
if (-not $exe) { throw 'The exact configured executable is missing.' }
$manifestPath = Join-Path $BuildDirectory "neuraldoom-build-$Configuration.json"
if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Build with Build-RBDOOM.ps1 first to record artifact identity.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
if ($manifest.sha256 -ne $hash -or $manifest.executable -ne $exe -or $manifest.configuration -ne $Configuration) {
    throw 'Executable does not match the selected build manifest. Rebuild before testing.'
}
Assert-NeuralShaderManifest -RepoRoot $RepoRoot -Manifest $manifest
$runRoot = Join-Path $RepoRoot ('captures/neural/smoke-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$saveBase = New-Item -ItemType Directory -Path (Join-Path $runRoot 'base') -Force
$resultPath = Join-Path $runRoot 'result.json'
$result = [ordered]@{
    schemaVersion = 1; status = 'FAIL'; profile = $Profile; build = $manifest
    width = $Width; height = $Height; hudScale = $HudScale; hudMaxAspect = $HudMaxAspect
    borderless = [bool]$Borderless; baseFieldOfView = $FieldOfView
    requestedFrames = $Frames; frameProgress = 0; exitCode = $null; reason = ''
    visualReview = 'PENDING'; artifacts = $runRoot
}
if (($ResizeWidth -eq 0) -ne ($ResizeHeight -eq 0) -or ($ResizeWidth -gt 0 -and ($ResizeWidth -lt 640 -or $ResizeHeight -lt 360))) { throw 'Resize requires both valid dimensions.' }
if ($Borderless -and $ResizeWidth -gt 0) { throw 'Borderless uses desktop dimensions; use a windowed run for the resize scenario.' }
$result.displayOutput = $DisplayOutput
$result.expectedHDR = $ExpectedHDR
$result.hdrDiagnostic = [bool]$HDRDiagnostic
$result.resizeWidth = $ResizeWidth
$result.resizeHeight = $ResizeHeight
$result.hdrActive = $false
$result.lightingVariant = $LightingVariant
$result.warmupFrames = $WarmupFrames
$result.gpuProfile = $null
$result.fixedTicProfiling = [bool]$GpuProfile
$result.expectedProbeLighting = $ExpectedProbeLighting
$result.probeLighting = $null
$result.lightGrid = $null
$result.rayTracingCapabilities = $null
$result.rayTracingDiagnostics = $RayTracingDiagnostics
$result.validationLayers = $ValidationLayers
$result.rayTracedAO = [bool]$RayTracedAO
$result.rayTracedContactShadows = [bool]$RayTracedContactShadows
$result.rayTracedGI = [bool]$RayTracedGI
$result.rayTracedReflections = [bool]$RayTracedReflections
if (($RayTracedContactShadows -or $RayTracedGI -or $RayTracedReflections) -and $manifest.features.rayTracing -ne 'ON') { throw 'Contact shadows, bounce and reflections require an RT build.' }
if ($RayTracingDebugViews -and (-not $RayTracedAO -or -not $RayTracedContactShadows -or -not $RayTracedGI -or -not $RayTracedReflections)) { throw 'The comparison-view check requires all four RT features.' }
$result.rayTracedAOStatus = @()
if ($RayTracedAO -and ($manifest.features.rayTracing -ne 'ON' -or $LightingVariant -eq 'NoSSAO')) { throw 'RTAO requires a ray-tracing build with SSAO enabled.' }
if (-not $GpuProfile -and $LightingVariant -ne 'Baseline') { throw 'Lighting variants require -GpuProfile.' }
$process = $null
try {
    if ($Profile -eq 'DLAA' -and $manifest.features.streamline -ne 'ON') {
        $result.status = 'SKIP'; $result.reason = 'Selected build has USE_STREAMLINE=OFF.'
        return
    }
    if ($Profile -eq 'DLAA') {
        foreach ($dll in @('sl.interposer.dll', 'sl.common.dll', 'sl.dlss.dll', 'nvngx_dlss.dll')) {
            if (-not (Test-Path -LiteralPath (Join-Path (Split-Path $exe) $dll))) {
                $result.status = 'SKIP'; $result.reason = "Missing local SDK component: $dll"
                return
            }
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'base/maps/mars_city2.resources'))) {
        $result.status = 'SKIP'; $result.reason = 'Required local BFG map data is unavailable.'
        return
    }
    # The engine exits successfully before opening its log if another instance owns this mutex.
    $existingGame = $null
    try { $existingGame = [Threading.Mutex]::OpenExisting('DOOM3') }
    catch [Threading.WaitHandleCannotBeOpenedException] { }
    if ($null -ne $existingGame) {
        $existingGame.Dispose()
        throw 'Another Doom 3 instance is running. Close it before starting a smoke check.'
    }
    $backend = @{ Native = 0; Validate = 1; DLAA = 2 }[$Profile]
    $sdk = if ($Profile -eq 'DLAA') { 1 } else { 0 }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $scriptLines = @(
        "set r_neuralBackend $backend", "set r_hdrDiagnostic $([int][bool]$HDRDiagnostic)", 'set r_screenFraction 100', "set r_renderMode $LegacyRenderMode",
        'set r_useTemporalAA 1', 'set r_antiAliasing 2', "set r_rayTracedAO $([int][bool]$RayTracedAO)", "set g_fov $FieldOfView",
        "set r_rayTracedContactShadows $([int][bool]$RayTracedContactShadows)", "set r_rayTracedGI $([int][bool]$RayTracedGI)", "set r_rayTracedReflections $([int][bool]$RayTracedReflections)",
        'set r_rayTracingDebug 0', 'set r_rayTracedGIStrength 1.125', 'set r_rayTracedGISamples 4', 'set r_neuralHistoryDebug 1',
        ('set swf_hudScale ' + $HudScale.ToString($culture)),
        ('set swf_hudMaxAspect ' + $HudMaxAspect.ToString($culture))
    )
    if ($RayTracedAO) { $scriptLines += @('set r_useSSAO 1', 'set r_useNewSSAOPass 1') }
    if ($GpuProfile) {
        # Bypass the background 15-Hz sleep using the engine's existing debug mode.
        # One simulation tick per render frame is a throughput workload, not normal play.
        $scriptLines += @('set r_swapInterval 0', 'set com_engineHz 60', 'set com_fixedTic 1',
            'set r_useShadowAtlas 1', 'set r_skipShadows 0', 'set r_lightScale 3', 'set r_useNewSSAOPass 1',
            "set r_useSSAO $([int]($LightingVariant -ne 'NoSSAO'))",
            "set r_useSSR $([int]($LightingVariant -ne 'NoSSR'))",
            "set r_shadowMapSamples $(if ($LightingVariant -eq 'Shadow4') { 4 } else { 16 })")
    }
    $scriptLines += @('rayTracingStatus', 'probeLightingStatus')
    if ($RayTracingDiagnostics -ne 'None') {
        $compiled = $manifest.features.rayTracing -eq 'ON'
        if (($RayTracingDiagnostics -eq 'BuildDisabled') -eq $compiled) { throw 'RT diagnostic expectation does not match the selected build.' }
        if ($RayTracingDiagnostics -eq 'MissingShader') {
            # Deliberate missing-bytecode fault in this run's own filesystem overlay.
            $shaderDirectory = New-Item -ItemType Directory -Path (Join-Path $saveBase.FullName 'renderprogs2/dxil/rt') -Force
            [IO.File]::WriteAllBytes((Join-Path $shaderDirectory.FullName 'ray_query.cs.dxil'), [byte[]]@())
        }
        $scriptLines += 'rayTracingTest'
        if ($RayTracingDiagnostics -ne 'MissingShader') { $scriptLines += 'rayTracingScene' }
    }
    $scriptLines += @('neuralInstallKeys startup', 'devmap game/mars_city2', "wait $WarmupFrames", 'set r_neuralHistoryDebug 1', 'r_neuralHistoryDebug')
    if ($RayTracingDiagnostics -in @('Synthetic', 'Scene')) { $scriptLines += @('rayTracingTest', 'rayTracingDynamicTest', 'rayTracingDynamicStatus') }
    if ($RayTracingDiagnostics -eq 'Scene') { $scriptLines += @('rayTracingScene', 'rayTracingTest') }
    $scriptLines += @('rayTracingAOStatus', 'hdrStatus', 'neuralHistoryStatus', 'neuralBackendStatus', 'probeLightingStatus', 'screenshot screenshots/before.png')
    if ($DLSSPresetMatrix) {
        if ($Profile -ne 'DLAA') { throw 'DLSS preset matrix requires the DLAA profile.' }
        foreach ($quality in @(0,1,2)) {
            $scriptLines += @("echo DLSS_PRESET_$quality", "set r_neuralDLSSQuality $quality", 'set r_neuralBackend 3', 'neuralHistoryReset', 'wait 90', 'neuralBackendStatus', "screenshot screenshots/dlss_$quality.png")
        }
        $scriptLines += @('set r_neuralBackend 2', 'neuralHistoryReset', 'wait 90', 'neuralBackendStatus')
    }
    $scriptLines += @('rayTracingContactStatus', 'rayTracingGIStatus', 'rayTracingReflectionStatus')
    if ($GpuProfile) {
        # Let the screenshot stall and its queued frames drain before requesting samples.
        $scriptLines += @('wait 30', "set r_gpuProfileFrames $Frames", "wait $($Frames + 60)")
    } else {
        $scriptLines += "wait $Frames"
    }
    $scriptLines += @('neuralHistoryStatus', 'neuralBackendStatus', 'probeLightingStatus',
        'neuralHistoryReset', 'wait 30', 'neuralHistoryStatus',
        'hdrStatus', 'screenshot screenshots/after.png'
    )
    # Capture live rollback before resizing, retaining comparable image dimensions.
    if ($RayTracedAO) {
        $scriptLines += @('rayTracingAOStatus', 'rayTracingAOToggle', 'wait 30', 'echo RT_HISTORY_r_rayTracedAO_0', 'neuralHistoryStatus', 'rayTracingAOStatus',
            'screenshot screenshots/rt_off.png', 'rayTracingAOToggle', 'wait 30', 'echo RT_HISTORY_r_rayTracedAO_1', 'neuralHistoryStatus')
    }
    if ($RayTracedContactShadows) {
        $scriptLines += @('rayTracingContactStatus', 'rayTracingContactToggle', 'wait 30', 'echo RT_HISTORY_r_rayTracedContactShadows_0', 'neuralHistoryStatus', 'rayTracingContactStatus',
            'screenshot screenshots/contacts_off.png', 'rayTracingContactToggle', 'wait 30', 'echo RT_HISTORY_r_rayTracedContactShadows_1', 'neuralHistoryStatus')
    }
    if ($RayTracedGI) {
        $scriptLines += @('rayTracingGIStatus', 'rayTracingBounceToggle', 'wait 30', 'echo RT_HISTORY_r_rayTracedGI_0', 'neuralHistoryStatus', 'rayTracingGIStatus',
            'screenshot screenshots/gi_off.png', 'rayTracingBounceToggle', 'wait 30', 'echo RT_HISTORY_r_rayTracedGI_1', 'neuralHistoryStatus')
    }
    if ($RayTracedReflections) {
        $scriptLines += @('rayTracingReflectionStatus', 'rayTracingReflectionToggle', 'wait 30', 'echo RT_HISTORY_r_rayTracedReflections_0', 'neuralHistoryStatus', 'rayTracingReflectionStatus',
            'screenshot screenshots/reflections_off.png', 'rayTracingReflectionToggle', 'wait 30', 'echo RT_HISTORY_r_rayTracedReflections_1', 'neuralHistoryStatus')
    }
    if ($RayTracingDebugViews) {
        $scriptLines += @('exec neural_rtx_keys.cfg', 'rayTracingDebugCycle', 'wait 30', 'screenshot screenshots/ao_visibility.png',
            'rayTracingDebugCycle', 'wait 30', 'screenshot screenshots/contact_visibility.png',
            'rayTracingDebugCycle', 'wait 30', 'screenshot screenshots/material_bounce.png',
            'rayTracingDebugCycle', 'wait 30', 'screenshot screenshots/material_albedo.png', 'rayTracingDebugCycle', 'wait 30',
            'screenshot screenshots/reflections.png', 'rayTracingDebugCycle', 'wait 30',
            'screenshot screenshots/reflection_roughness.png', 'rayTracingDebugCycle', 'wait 30')
    }
    if ($ResizeWidth -gt 0) {
        $scriptLines += @("set r_windowWidth $ResizeWidth", "set r_windowHeight $ResizeHeight", 'vid_restart', 'wait 90', 'hdrStatus', 'neuralHistoryStatus', 'screenshot screenshots/resized.png')
    }
    $scriptLines += @('rayTracingAOStatus', 'rayTracingContactStatus', 'rayTracingGIStatus', 'rayTracingReflectionStatus', 'rayTracingDynamicStatus', 'echo NEURAL_SMOKE_COMPLETE', 'quit')
    $scriptLines | Set-Content -LiteralPath (Join-Path $saveBase.FullName 'neural_smoke.cfg') -Encoding ASCII
    # Values are scalar/validated; quote filesystem paths explicitly for Windows argv.
    # Win32 stores the command line in MAX_STRING_CHARS (1024 bytes).
    # Keep only initialization settings here; use the cfg for the scenario.
    $launchArgs = @(
        '+set', 'fs_basepath', ('"' + $RepoRoot + '"'), '+set', 'fs_savepath', ('"' + $runRoot + '"'),
        '+set', 'r_graphicsAPI', 'dx12', '+set', 'r_fullscreen', $(if ($Borderless) { -2 } else { 0 }),
        '+set', 'r_useValidationLayers', $ValidationLayers,
        '+set', 'r_windowWidth', $Width, '+set', 'r_windowHeight', $Height,
        '+set', 'r_neuralCompatibilityEnable', '0', '+set', 'r_streamlineEnable', $sdk,
        '+set', 'r_streamlineApplicationId', '0', '+set', 'r_neuralBackend', $backend,
        '+set', 'logFileName', 'smoke.log', '+set', 'logFile', '2',
        '+set', 's_noSound', '1', '+set', 'r_hdrOutput', $(if ($DisplayOutput -eq 'AutoHDR') { 1 } else { 0 }),
        '+exec', 'neural_smoke.cfg'
    )
    if ([Text.Encoding]::UTF8.GetByteCount(($launchArgs -join ' ')) -ge 1024) { throw 'Launch arguments exceed the engine command-line limit; use a shorter checkout path.' }
    $process = Start-Process -FilePath $exe -ArgumentList $launchArgs -WorkingDirectory $RepoRoot -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $result.reason = "Timed out after $TimeoutSeconds seconds."
        throw $result.reason
    }
    $process.Refresh()
    $result.exitCode = $process.ExitCode
    if ($process.ExitCode -ne 0) { throw "Engine exited with code $($process.ExitCode)." }
    $log = Get-Content -LiteralPath (Join-Path $saveBase.FullName 'smoke.log') -Raw
    if ($log -notmatch 'NEURAL_SMOKE_COMPLETE') { throw 'Gameplay script did not complete.' }
    if ($log -match '(?im)FATAL ERROR|D3D12 device removed|Unknown command') { throw 'Engine log contains fatal/device/command errors.' }
    if ($DLSSPresetMatrix) {
        $modes = [regex]::Matches($log, 'Neural temporal backend: Streamline DLSS, initialized yes, evaluated \d+, presented (\d+), rejected (\d+), epoch \d+, render (\d+)x(\d+), output (\d+)x(\d+), last (Quality|Balanced|Performance)')
        if ($modes.Count -ne 3) { throw 'Missing successful DLSS preset evaluation evidence.' }
        $previousWidth = $Width + 1; $previousFrames = 0
        foreach ($mode in $modes) {
            if ([int]$mode.Groups[1].Value -le $previousFrames -or [int]$mode.Groups[2].Value -ne 0 -or [int]$mode.Groups[3].Value -ge $previousWidth -or [int]$mode.Groups[5].Value -ne $Width -or [int]$mode.Groups[6].Value -ne $Height) { throw 'DLSS presets did not lower input resolution while preserving output and successful presentation.' }
            $previousFrames = [int]$mode.Groups[1].Value; $previousWidth = [int]$mode.Groups[3].Value
        }
    }
    # Frontend-thread Printf goes to OutputDebugString on Windows, not the file log.
    # Query the actual epoch from the main-thread console after each lighting edit.
    $resetStates = [regex]::Matches($log, 'RT_HISTORY_r_rayTraced\w+_[01][ \t]*\r?\nNeural temporal history: epoch (\d+), pending none, lastReset ([^\r\n]+)')
    $expectedLightingResets = 2 * ([int][bool]$RayTracedAO + [int][bool]$RayTracedContactShadows + [int][bool]$RayTracedGI + [int][bool]$RayTracedReflections)
    if ($resetStates.Count -ne $expectedLightingResets) { throw 'Missing per-toggle history state.' }
    $previousEpoch = -1L
    foreach ($state in $resetStates) {
        $epoch = [long]$state.Groups[1].Value
        if ($epoch -le $previousEpoch -or $state.Groups[2].Value -notmatch 'lighting-change') {
            throw 'Direct RTX cvar change failed to advance lighting history.'
        }
        $previousEpoch = $epoch
    }
    $result.lightingHistoryResets = $resetStates.Count
    $aoSamples = [regex]::Matches($log, 'RTAO_STATUS active=([01]) frames=(\d+) samples=(\d+) matched=(\d+) occluded=(\d+)')
    $result.rayTracedAOStatus = @($aoSamples | ForEach-Object {
        [pscustomobject]@{ active = $_.Groups[1].Value -eq '1'; frames = [int]$_.Groups[2].Value;
            samples = [int]$_.Groups[3].Value; matched = [int]$_.Groups[4].Value; occluded = [int]$_.Groups[5].Value }
    })
    $ao = $result.rayTracedAOStatus
    if ($RayTracedAO) {
        if ($ao.Count -ne 4 -or -not $ao[0].active -or -not $ao[1].active -or $ao[2].active -or -not $ao[3].active -or
            $ao[1].frames -le $ao[0].frames -or $ao[3].frames -le $ao[2].frames -or
            $ao[2].frames -gt $ao[1].frames + 3 -or $ao[1].matched -le 0 -or $ao[1].occluded -le 0 -or
            $ao[3].matched -le 0 -or $ao[3].occluded -le 0) {
            throw 'Ray-traced AO did not shade static receivers, stop on disable, or resume after enable/resize.'
        }
    } elseif ($ao.Count -ne 2 -or @($ao | Where-Object { $_.active -or $_.frames -ne 0 }).Count -gt 0) {
        throw 'Disabled AO unexpectedly allocated or dispatched gameplay rays.'
    }
    if ($RayTracingDiagnostics -eq 'BuildDisabled') {
        if ($log -notmatch 'RT_TEST status=SKIP reason=build-disabled' -or $log -notmatch 'RT_SCENE status=SKIP reason=build-disabled' -or $log -match 'RT_BUILD|RT_TRACE') { throw 'Disabled RT build did not preserve the no-work path.' }
    } elseif ($RayTracingDiagnostics -eq 'MissingShader') {
        if ($log -notmatch 'RT_DIAGNOSTIC_ERROR reason=missing-shader' -or $log -notmatch 'RT_TEST status=FAIL reason=initialization-or-trace' -or $log -match 'RT_BUILD|RT_TRACE') { throw 'Missing RT shader did not fail safely before GPU work.' }
    } elseif ($RayTracingDiagnostics -in @('Synthetic', 'Scene')) {
        $expectedTests = if ($RayTracingDiagnostics -eq 'Scene') { 3 } else { 2 }
        if ($log -notmatch 'RT_DYNAMIC_TEST status=PASS phases=4 mismatches=0') { throw 'Dynamic ray insertion/movement/removal diagnostic failed.' }
        if ([regex]::Matches($log, 'RT_TEST status=PASS phases=2 rays=24 mismatches=0').Count -ne $expectedTests -or $log -match 'RT_\w+ status=FAIL|RT_DIAGNOSTIC_ERROR') { throw 'Ray intersection or instance-update checks failed.' }
        if ($log -notmatch 'RT_SCENE status=SKIP reason=no-world') { throw 'Missing safe no-world RT diagnostic result.' }
        if ($RayTracingDiagnostics -eq 'Scene') {
            $scene = [regex]::Match($log, 'RT_SCENE status=PASS models=(\d+) surfaces=(\d+) excluded=(\d+) triangles=(\d+) rays=131072 hits=(\d+) behindHits=(\d+) referenceRays=32 mismatches=0 invalid=0')
            if (-not $scene.Success -or [int]$scene.Groups[4].Value -le 0 -or [int]$scene.Groups[6].Value -le 0) { throw 'Static-world ray tracing did not pass reference and behind-camera checks.' }
            $result.rayTracingScene = [pscustomobject]@{ triangles = [int]$scene.Groups[4].Value; rays = 131072; hits = [int]$scene.Groups[5].Value; behindHits = [int]$scene.Groups[6].Value; referenceRays = 32 }
            $rtCapture = Join-Path $saveBase.FullName 'screenshots/rt_static_world.png'
            if (-not (Test-Path -LiteralPath $rtCapture)) { throw 'Missing ray-traced static-world panorama.' }
        }
    }
    foreach ($feature in @('Contact', 'GI')) {
        $pattern = if ($feature -eq 'Contact') {
            'RTCONTACT_STATUS active=([01]) frames=(\d+) lights=(\d+) dispatches=(\d+) samples=(\d+) matched=(\d+) hits=(\d+) modified=(\d+) invalid=(\d+)'
        } else {
            'RTGI_STATUS active=([01]) frames=(\d+) lights=(\d+) samples=(\d+) matched=(\d+) hits=(\d+) colored=(\d+) modified=(\d+) invalid=(\d+)'
        }
        $samples = @([regex]::Matches($log, $pattern) | ForEach-Object {
            [pscustomobject]@{ active = $_.Groups[1].Value -eq '1'; frames = [int]$_.Groups[2].Value;
                lights = [int]$_.Groups[3].Value; modified = [int]$_.Groups[8].Value; invalid = [int]$_.Groups[9].Value; raw = $_.Value }
        })
        $result["rayTracing${feature}Status"] = $samples
        $enabled = if ($feature -eq 'Contact') { $RayTracedContactShadows } else { $RayTracedGI }
        if ($enabled) {
            if ($samples.Count -ne 4 -or -not $samples[0].active -or -not $samples[1].active -or $samples[2].active -or -not $samples[3].active -or
                $samples[1].frames -le $samples[0].frames -or $samples[2].frames -gt $samples[1].frames + 3 -or $samples[3].frames -le $samples[2].frames -or
                $samples[1].modified -le 0 -or $samples[3].modified -le 0 -or @($samples | Where-Object { $_.invalid -ne 0 }).Count -gt 0) {
                throw "$feature failed shading, live disable/enable, resize, or finite-value checks."
            }
        } elseif ($samples.Count -ne 2 -or @($samples | Where-Object { $_.active -or $_.frames -ne 0 }).Count -gt 0) {
            throw "Disabled $feature unexpectedly allocated or dispatched gameplay rays."
        }
    }
    $reflectionSamples = @([regex]::Matches($log, 'RTREFLECTION_STATUS active=([01]) frames=(\d+)(?: width=(\d+) height=(\d+) fullResolution=1 samples=(\d+) matched=(\d+) rays=(\d+) hits=(\d+) modified=(\d+) invalid=(\d+))?') | ForEach-Object {
        [pscustomobject]@{ active = $_.Groups[1].Value -eq '1'; frames = [int]$_.Groups[2].Value;
            width = [int]$_.Groups[3].Value; height = [int]$_.Groups[4].Value; modified = [int]$_.Groups[9].Value; invalid = [int]$_.Groups[10].Value }
    })
    $result.rayTracingReflectionStatus = $reflectionSamples
    if ($RayTracedReflections) {
        if ($reflectionSamples.Count -ne 4 -or -not $reflectionSamples[0].active -or -not $reflectionSamples[1].active -or
            $reflectionSamples[2].active -or -not $reflectionSamples[3].active -or
            $reflectionSamples[1].frames -le $reflectionSamples[0].frames -or
            $reflectionSamples[2].frames -gt $reflectionSamples[1].frames + 3 -or
            $reflectionSamples[3].frames -le $reflectionSamples[2].frames -or
            $reflectionSamples[1].modified -le 0 -or $reflectionSamples[3].modified -le 0 -or
            @($reflectionSamples | Where-Object { $_.invalid -ne 0 }).Count -gt 0) { throw 'Reflections failed coverage, toggle, resume or finite-value checks.' }
        $lastWidth = if ($ResizeWidth -gt 0) { $ResizeWidth } else { $Width }
        $lastHeight = if ($ResizeWidth -gt 0) { $ResizeHeight } else { $Height }
        if ($reflectionSamples[1].width -ne $Width -or $reflectionSamples[1].height -ne $Height -or
            $reflectionSamples[3].width -ne $lastWidth -or $reflectionSamples[3].height -ne $lastHeight) { throw 'Reflection rays did not run at the full requested resolution.' }
    } elseif ($reflectionSamples.Count -ne 2 -or @($reflectionSamples | Where-Object { $_.active -or $_.frames -ne 0 }).Count -gt 0) {
        throw 'Disabled reflections unexpectedly dispatched gameplay rays.'
    }
    if ($RayTracingDebugViews) {
        $savedConfig = Get-Content -LiteralPath (Join-Path $saveBase.FullName 'D3BFGConfig.cfg') -Raw
        if ($savedConfig -notmatch 'bind\s+"?F4"?\s+"toggle r_rayTracedGI; neuralHistoryReset"' -or
            $savedConfig -notmatch 'bind\s+"?F11"?\s+"rayTracingToggle"' -or [regex]::Matches($log, 'Ray-tracing view [0-6]:').Count -ne 7) { throw 'RTX example bindings or debug-view cycle failed.' }
    }
    $probes = [regex]::Matches($log, 'PROBE_LIGHTING world=1 map=(\S+) probes=(\d+) irradianceReady=(\d+) radianceReady=(\d+) complete=(\d+) defaulted=(\d+) unloaded=(\d+)')
    $selections = [regex]::Matches($log, 'PROBE_SELECTION valid=1 area=(-?\d+) diffuseFallback=(\d) specularFallbacks=(\d) activeSpecularFallbacks=(\d)')
    if ($probes.Count -lt 2 -or $selections.Count -lt 2) { throw 'Missing gameplay probe-lighting diagnostics.' }
    $probeStates = @()
    # The startup diagnostic may report a menu world; validate the two gameplay samples.
    for ($i = 2; $i -ge 1; $i--) {
        $sample = $probes[$probes.Count - $i]; $selection = $selections[$selections.Count - $i]
        $state = [pscustomobject]@{
            map = $sample.Groups[1].Value; probes = [int]$sample.Groups[2].Value
            irradianceReady = [int]$sample.Groups[3].Value; radianceReady = [int]$sample.Groups[4].Value
            complete = [int]$sample.Groups[5].Value; defaulted = [int]$sample.Groups[6].Value; unloaded = [int]$sample.Groups[7].Value
            area = [int]$selection.Groups[1].Value; diffuseFallback = [int]$selection.Groups[2].Value
            specularFallbacks = [int]$selection.Groups[3].Value; activeSpecularFallbacks = [int]$selection.Groups[4].Value
        }
        $probeStates += $state
        $result.probeLighting = $probeStates
        if ($state.map -notmatch '^maps/game/mars_city2(?:\.map)?$' -or $state.probes -le 0 -or $state.area -lt 0) { throw 'Probe diagnostics did not describe the expected gameplay world.' }
        if ($ExpectedProbeLighting -eq 'Local' -and ($state.complete -ne $state.probes -or $state.defaulted -ne 0 -or $state.unloaded -ne 0 -or $state.diffuseFallback -ne 0 -or $state.activeSpecularFallbacks -ne 0)) {
            throw 'Expected complete map lighting bakes and a local probe selection.'
        }
        if ($ExpectedProbeLighting -eq 'Fallback' -and ($state.irradianceReady -ne 0 -or $state.radianceReady -ne 0 -or $state.diffuseFallback -ne 1 -or $state.specularFallbacks -ne 3 -or $state.activeSpecularFallbacks -lt 1)) {
            throw 'Expected missing map lighting bakes and the built-in lighting fallback.'
        }
    }
    $grid = [regex]::Matches($log, 'LIGHT_GRID enabled=([01]) areas=(\d+) ready=(\d+) defaulted=(\d+) unloaded=(\d+) empty=(\d+)')
    if ($grid.Count -lt 2) { throw 'Missing light-grid diagnostic.' }
    $lastGrid = $grid[$grid.Count - 1]
    $result.lightGrid = [pscustomobject]@{
        enabled = $lastGrid.Groups[1].Value -eq '1'; areas = [int]$lastGrid.Groups[2].Value
        ready = [int]$lastGrid.Groups[3].Value; defaulted = [int]$lastGrid.Groups[4].Value; unloaded = [int]$lastGrid.Groups[5].Value
        emptyAreas = [int]$lastGrid.Groups[6].Value
    }
    $rt = [regex]::Match($log, 'RAY_TRACING_STATUS device=1 api=(\w+) accelStruct=([01]) pipeline=([01]) rayQuery=([01]) sceneImplemented=([01])')
    if (-not $rt.Success) { throw 'Missing ray-tracing capability diagnostic.' }
    $result.rayTracingCapabilities = [pscustomobject]@{
        api = $rt.Groups[1].Value; accelerationStructures = $rt.Groups[2].Value -eq '1'
        pipelines = $rt.Groups[3].Value -eq '1'; inlineRayQueries = $rt.Groups[4].Value -eq '1'
        sceneImplemented = $rt.Groups[5].Value -eq '1'
    }
    if ($GpuProfile) {
        if ($log -notmatch "GPU_PROFILE_COMPLETE samples=$Frames file=gpu_profile.csv") { throw 'GPU profile did not complete.' }
        $result.gpuProfile = & (Join-Path $PSScriptRoot 'Measure-NeuralGpuProfile.ps1') -Path (Join-Path $saveBase.FullName 'gpu_profile.csv') -ExpectedSamples $Frames -Width $Width -Height $Height
    }
    $history = [regex]::Matches($log, 'Neural temporal history: epoch (\d+),[^\r\n]+trackedView valid at frame (\d+)')
    if ($history.Count -lt 3) { throw 'Missing primary-view history evidence.' }
    $result.frameProgress = [int]$history[1].Groups[2].Value - [int]$history[0].Groups[2].Value
    if ($result.frameProgress -lt $Frames) { throw 'Insufficient primary-view frame progress.' }
    if ([long]$history[2].Groups[1].Value -le [long]$history[1].Groups[1].Value) { throw 'Manual history reset did not advance the epoch.' }
    if ($Profile -ne 'Native') {
        $states = [regex]::Matches($log, 'Neural temporal backend: [^\r\n]+evaluated (\d+), (?:presented (\d+), )?rejected (\d+)')
        if ($states.Count -lt 2) { throw 'Missing backend evaluation evidence.' }
        $last = $states[$states.Count - 1]
        if ([long]$last.Groups[1].Value -lt $Frames -or [long]$last.Groups[3].Value -ne 0) { throw 'Backend did not evaluate enough frames without rejection.' }
        if ($Profile -eq 'DLAA' -and [long]$last.Groups[2].Value -lt $Frames) { throw 'DLAA did not present enough evaluated frames.' }
    }
    $hdr = [regex]::Matches($log, 'HDR content: active=(\d)')
    if ($hdr.Count -lt 2) { throw 'Missing HDR content status.' }
    $result.hdrActive = $hdr[$hdr.Count - 1].Groups[1].Value -eq '1'
    if ($ExpectedHDR -eq 'Active' -and -not $result.hdrActive) { throw 'HDR was requested for validation but remained inactive.' }
    if (($ExpectedHDR -eq 'SDR' -or $DisplayOutput -eq 'SDR') -and $result.hdrActive) { throw 'Expected SDR fallback, but HDR content is active.' }
    $readbacks = [regex]::Matches($log, 'HDR readback: stage=composition format=RGBA16F width=(\d+) height=(\d+) maximum=([0-9.]+) aboveOne=(\d+) invalid=(\d+) active=(\d)')
    foreach ($readback in $readbacks) {
        if ([long]$readback.Groups[5].Value -ne 0) { throw 'HDR composition contains invalid values.' }
    }
    if (($result.hdrActive -or $HDRDiagnostic) -and ($readbacks.Count -lt 2 -or [long]$readbacks[0].Groups[4].Value -eq 0)) { throw 'No readback evidence of HDR values above the SDR ceiling.' }
    $presented = [regex]::Matches($log, 'HDR readback: stage=scRGB format=RGBA16F width=(\d+) height=(\d+) maximum=([0-9.]+) aboveOne=(\d+) invalid=(\d+) active=(\d+) negative=(\d+)')
    foreach ($sample in $presented) {
        if ([long]$sample.Groups[5].Value -ne 0 -or [long]$sample.Groups[7].Value -ne 0) { throw 'Invalid scRGB presentation values.' }
        if ($log -match 'transport=scRGB-FP16 windowsHDR=0' -and [double]::Parse($sample.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture) -gt 1.001) { throw 'SDR presentation exceeded normalized white.' }
    }
    if ($DisplayOutput -eq 'AutoHDR' -and $log -match 'transport=scRGB-FP16' -and $presented.Count -lt 2) { throw 'Missing scRGB presentation readback.' }
    if ($ResizeWidth -gt 0 -and ($history.Count -lt 4 -or [long]$history[$history.Count - 1].Groups[1].Value -le [long]$history[$history.Count - 2].Groups[1].Value)) { throw 'Resize did not advance history epoch.' }
    $names = @('before', 'after')
    if ($RayTracedAO) { $names += 'rt_off' }
    if ($RayTracedContactShadows) { $names += 'contacts_off' }
    if ($RayTracedGI) { $names += 'gi_off' }
    if ($RayTracedReflections) { $names += 'reflections_off' }
    if ($RayTracingDebugViews) { $names += @('ao_visibility', 'contact_visibility', 'material_bounce', 'material_albedo', 'reflections', 'reflection_roughness') }
    if ($ResizeWidth -gt 0) { $names += 'resized' }
    foreach ($name in $names) {
        $capture = Join-Path $saveBase.FullName "screenshots/$name.png"
        if (-not (Test-Path -LiteralPath $capture)) { throw "Missing screenshot: $name" }
        $png = [IO.File]::ReadAllBytes($capture)
        if ($png.Length -lt 33 -or [BitConverter]::ToString($png, 0, 8) -ne '89-50-4E-47-0D-0A-1A-0A') { throw "Invalid PNG: $name" }
        $captureWidth = $png[16] * 16777216 + $png[17] * 65536 + $png[18] * 256 + $png[19]
        $captureHeight = $png[20] * 16777216 + $png[21] * 65536 + $png[22] * 256 + $png[23]
        $expectedWidth = if ($name -eq 'resized') { $ResizeWidth } else { $Width }; $expectedHeight = if ($name -eq 'resized') { $ResizeHeight } else { $Height }
        if ($captureWidth -ne $expectedWidth -or $captureHeight -ne $expectedHeight) { throw "Capture dimensions differ from requested output: ${captureWidth}x$captureHeight" }
    }
    $result.status = 'PASS'
    $result.reason = 'Gameplay completed with primary-view progress, reset epoch, captures, and requested backend evidence.'
} catch {
    $result.reason = $_.Exception.Message
} finally {
    if ($null -ne $process) {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit(5000) | Out-Null }
        $process.Dispose()
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Host "$($result.status): $($result.reason)"
    Write-Host "Results: $resultPath"
    if ($PassThru) { Write-Output ([pscustomobject]$result) }
}
if ($result.status -eq 'FAIL') { throw $result.reason }
