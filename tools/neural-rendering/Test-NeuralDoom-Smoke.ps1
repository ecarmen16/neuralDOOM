[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$BuildDirectory,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo',
    [ValidateSet('Native', 'Validate', 'DLAA')][string]$Profile = 'Native',
    [ValidateRange(640, 7680)][int]$Width = 1280,
    [ValidateRange(360, 4320)][int]$Height = 720,
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
$runRoot = Join-Path $RepoRoot ('captures/neural/smoke-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$saveBase = New-Item -ItemType Directory -Path (Join-Path $runRoot 'base') -Force
$resultPath = Join-Path $runRoot 'result.json'
$result = [ordered]@{
    schemaVersion = 1; status = 'FAIL'; profile = $Profile; build = $manifest
    width = $Width; height = $Height; hudScale = $HudScale; hudMaxAspect = $HudMaxAspect
    requestedFrames = $Frames; frameProgress = 0; exitCode = $null; reason = ''
    visualReview = 'PENDING'; artifacts = $runRoot
}
if (($ResizeWidth -eq 0) -ne ($ResizeHeight -eq 0) -or ($ResizeWidth -gt 0 -and ($ResizeWidth -lt 640 -or $ResizeHeight -lt 360))) { throw 'Resize requires both valid dimensions.' }
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
        'set r_useTemporalAA 1', 'set r_antiAliasing 2',
        ('set swf_hudScale ' + $HudScale.ToString($culture)),
        ('set swf_hudMaxAspect ' + $HudMaxAspect.ToString($culture))
    )
    if ($GpuProfile) {
        # Bypass the background 15-Hz sleep using the engine's existing debug mode.
        # One simulation tick per render frame is a throughput workload, not normal play.
        $scriptLines += @('set r_swapInterval 0', 'set com_engineHz 60', 'set com_fixedTic 1',
            'set r_useShadowAtlas 1', 'set r_skipShadows 0', 'set r_lightScale 3', 'set r_useNewSSAOPass 1',
            "set r_useSSAO $([int]($LightingVariant -ne 'NoSSAO'))",
            "set r_useSSR $([int]($LightingVariant -ne 'NoSSR'))",
            "set r_shadowMapSamples $(if ($LightingVariant -eq 'Shadow4') { 4 } else { 16 })")
    }
    $scriptLines += @('devmap game/mars_city2', "wait $WarmupFrames", 'hdrStatus', 'neuralHistoryStatus', 'neuralBackendStatus', 'screenshot screenshots/before.png')
    if ($GpuProfile) {
        # Let the screenshot stall and its queued frames drain before requesting samples.
        $scriptLines += @('wait 30', "set r_gpuProfileFrames $Frames", "wait $($Frames + 60)")
    } else {
        $scriptLines += "wait $Frames"
    }
    $scriptLines += @('neuralHistoryStatus', 'neuralBackendStatus',
        'neuralHistoryReset', 'wait 30', 'neuralHistoryStatus',
        'hdrStatus', 'screenshot screenshots/after.png'
    )
    if ($ResizeWidth -gt 0) {
        $scriptLines += @("set r_windowWidth $ResizeWidth", "set r_windowHeight $ResizeHeight", 'vid_restart', 'wait 90', 'hdrStatus', 'neuralHistoryStatus', 'screenshot screenshots/resized.png')
    }
    $scriptLines += @('echo NEURAL_SMOKE_COMPLETE', 'quit')
    $scriptLines | Set-Content -LiteralPath (Join-Path $saveBase.FullName 'neural_smoke.cfg') -Encoding ASCII
    # Values are scalar/validated; quote filesystem paths explicitly for Windows argv.
    # Win32 stores the command line in MAX_STRING_CHARS (1024 bytes).
    # Keep only initialization settings here; use the cfg for the scenario.
    $launchArgs = @(
        '+set', 'fs_basepath', ('"' + $RepoRoot + '"'), '+set', 'fs_savepath', ('"' + $runRoot + '"'),
        '+set', 'r_graphicsAPI', 'dx12', '+set', 'r_fullscreen', '0',
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
    if ($ResizeWidth -gt 0 -and ($history.Count -lt 4 -or [long]$history[3].Groups[1].Value -le [long]$history[2].Groups[1].Value)) { throw 'Resize did not advance history epoch.' }
    $names = @('before', 'after')
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
