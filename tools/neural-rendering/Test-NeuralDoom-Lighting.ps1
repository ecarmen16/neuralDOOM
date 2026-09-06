[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$BuildDirectory,
    [ValidateSet('Native', 'DLAA')][string]$Profile = 'Native',
    [ValidateRange(640, 7680)][int]$Width = 2560,
    [ValidateRange(360, 4320)][int]$Height = 720,
    [ValidateRange(60, 3600)][int]$Frames = 300,
    [ValidateRange(180, 3600)][int]$WarmupFrames = 300,
    [ValidateRange(30, 600)][int]$TimeoutSeconds = 180
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) { $BuildDirectory = Join-Path $RepoRoot 'build' }
$reportRoot = Join-Path $RepoRoot ('captures/neural/lighting-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
$report = [ordered]@{
    schemaVersion = 1; status = 'FAIL'; profile = $Profile; width = $Width; height = $Height
    scene = 'game/mars_city2 at the default spawn, no input; world simulation remains active'
    warmupFrames = $WarmupFrames; requestedSamplesPerRun = $Frames; runs = @()
    method = 'Two sweeps in reversed order. Fixed lighting variants, SDR output, native resolution, TAA or DLAA. com_fixedTic=1 bypasses background sleep and runs one simulation tick per rendered frame; this is a throughput workload, not real-time play. Screenshot and 30 settling frames precede each capture. GPU timings exclude present/CPU; scene animation and GPU clocks can vary.'
    reason = ''; artifacts = $reportRoot
}
try {
    # Run sequentially: all Doom 3 builds share a single-instance mutex.
    foreach ($variant in @('Baseline', 'NoSSAO', 'NoSSR', 'Shadow4', 'Shadow4', 'NoSSR', 'NoSSAO', 'Baseline')) {
        Write-Step "Lighting $Profile $variant ($($report.runs.Count + 1)/8)"
        $run = & (Join-Path $PSScriptRoot 'Test-NeuralDoom-Smoke.ps1') -RepoRoot $RepoRoot -BuildDirectory $BuildDirectory -Profile $Profile -Width $Width -Height $Height -Frames $Frames -WarmupFrames $WarmupFrames -TimeoutSeconds $TimeoutSeconds -GpuProfile -LightingVariant $variant -PassThru
        $report.runs += $run
        if ($run.status -ne 'PASS') { throw "Lighting run $variant did not pass: $($run.reason)" }
    }
    $report.status = 'PASS'
    $report.reason = 'All eight runs completed with verified GPU samples and gameplay evidence.'
} catch {
    $report.reason = $_.Exception.Message
} finally {
    $path = Join-Path $reportRoot 'lighting.json'
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Host "$($report.status): $($report.reason)"
    Write-Host "Lighting report: $path"
}
if ($report.status -ne 'PASS') { throw $report.reason }
