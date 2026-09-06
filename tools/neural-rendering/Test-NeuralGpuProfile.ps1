[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Common.ps1')
$root = Join-Path (Resolve-NeuralRepoRoot) ('captures/neural/gpu-profile-fixture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$path = Join-Path $root 'profile.csv'
$reader = Join-Path $PSScriptRoot 'Measure-NeuralGpuProfile.ps1'
$valid = @('query_frame,width,height,MRB_GPU_TIME_us,MRB_SSAO_PASS_us', '10,1280,720,1000,', '11,1280,720,3000,0')
$valid | Set-Content -LiteralPath $path -Encoding ASCII
$result = & $reader -Path $path -ExpectedSamples 2 -Width 1280 -Height 720
if ($result.passes.MRB_GPU_TIME_us.medianMs -ne 2 -or $result.passes.MRB_GPU_TIME_us.p95Ms -ne 3) { throw 'Incorrect microsecond conversion or statistics.' }
if ($result.passes.MRB_SSAO_PASS_us.measuredSamples -ne 1 -or $result.passes.MRB_SSAO_PASS_us.missingSamples -ne 1 -or $result.passes.MRB_SSAO_PASS_us.medianMs -ne 0) { throw 'Missing pass was confused with measured zero.' }
foreach ($badRow in @('10,1280,720,3000,0', '11,1920,720,3000,0', '11,1280,720,NaN,0', '11,1280,720,-1,0', '11,1280,720,0,0', '11,1280,720,,0')) {
    @($valid[0], $valid[1], $badRow) | Set-Content -LiteralPath $path -Encoding ASCII
    $rejected = $false
    try { $null = & $reader -Path $path -ExpectedSamples 2 -Width 1280 -Height 720 } catch { $rejected = $true }
    if (-not $rejected) { throw "Invalid sample was accepted: $badRow" }
}
@($valid[0], $valid[1]) | Set-Content -LiteralPath $path -Encoding ASCII
$rejected = $false
try { $null = & $reader -Path $path -ExpectedSamples 2 -Width 1280 -Height 720 } catch { $rejected = $true }
if (-not $rejected) { throw 'Incomplete capture was accepted.' }
Write-Host 'PASS: GPU units, median/p95, missing versus zero, invalid samples, duplicate frames, resize, and incomplete capture.'
