[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'EmbeddedNR.ps1')
$repo = Resolve-NeuralRepoRoot
$fixture = Join-Path $repo ('captures/neural/nr-fixture-' + [guid]::NewGuid().ToString('N'))
$build = Join-Path $fixture 'build-streamline/RelWithDebInfo'
$tree = Split-Path $build
$shaderRoot = Join-Path $fixture 'base/renderprogs2/dxil/rt'
New-Item -ItemType Directory -Path $build, $shaderRoot, (Join-Path $fixture 'base/maps') -Force | Out-Null
# All fixture files are plain text. No actual DLL is copied or loaded.
$exact = Join-Path $build 'neuralDoom.exe'
'verified-engine-fixture' | Set-Content -LiteralPath $exact
'old-engine-fixture' | Set-Content -LiteralPath (Join-Path $fixture 'neuralDoom.exe')
$exact | Set-Content -LiteralPath (Join-Path $tree 'neuraldoom-artifact-RelWithDebInfo.txt')
foreach ($name in @('sl.interposer.dll', 'sl.common.dll', 'sl.dlss.dll', 'nvngx_dlss.dll')) {
    'sdk-text-fixture' | Set-Content -LiteralPath (Join-Path $build $name)
    'sdk-text-fixture' | Set-Content -LiteralPath (Join-Path $fixture $name)
}
foreach ($name in @('neuraldoom-reshade64.dll', 'renodx-dlss5.addon64', 'nvngx_dlssnr.dll')) {
    'local-component-text-fixture' | Set-Content -LiteralPath (Join-Path $fixture $name)
}
$ini = Join-Path $fixture 'reshade.ini'
$config = "[GENERAL]`r`nTest=keep`r`n[RenoDX.DLSS5]`r`nNeuralUplift=0`r`nNREnableUpscaling=1`r`nNRIntensity=1.87`r`n[OTHER]`r`nUntouched=yes`r`n"
[IO.File]::WriteAllText($ini, $config)
'map-text-fixture' | Set-Content -LiteralPath (Join-Path $fixture 'base/maps/mars_city2.resources')
foreach ($shader in @('ray_query', 'ambient_occlusion', 'contact_shadows', 'visibility_debug', 'material_atlas',
    'diffuse_bounce', 'bounce_composite', 'reflections', 'reflection_filter', 'reflection_composite')) {
    'shader-text-fixture' | Set-Content -LiteralPath (Join-Path $shaderRoot "$shader.cs.dxil")
}
$manifest = @{
    schemaVersion = 2; sha256 = (Get-FileHash -LiteralPath $exact).Hash; executable = $exact
    configuration = 'RelWithDebInfo'; commit = 'fixture'; dirty = $false
    features = @{ dx12 = 'ON'; rayTracing = 'ON'; streamline = 'ON' }
    shaders = @(Get-NeuralShaderManifest -RepoRoot $fixture -RayTracing $true)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tree 'neuraldoom-build-RelWithDebInfo.json')
$launcher = Join-Path $PSScriptRoot 'Start-NeuralDoom-Dogfood.ps1'
function Start-Process { throw 'A read-only/preparation test attempted to launch a process.' }
$before = @{}
Get-ChildItem -LiteralPath $fixture -File | ForEach-Object { $before[$_.Name] = (Get-FileHash -LiteralPath $_.FullName).Hash }
& $launcher -RepoRoot $fixture -Profile NR -RayTracedAO -RayTracedContactShadows -RayTracedGI -RayTracedReflections -DisplayOutput AutoHDR -ValidateOnly
foreach ($name in $before.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $fixture $name)).Hash -ne $before[$name]) { throw "Readiness check changed $name" }
}
if (Test-Path -LiteralPath (Join-Path $fixture 'captures/dogfood')) { throw 'NR readiness check wrote player settings.' }
function Expect-NRFailure {
    param([string]$Pattern)
    $caught = $false
    try { & $launcher -RepoRoot $fixture -Profile NR -ValidateOnly } catch {
        if ($_.Exception.Message -notlike $Pattern) { throw }
        $caught = $true
    }
    if (-not $caught) { throw "Expected NR readiness rejection: $Pattern" }
}
'proxy-text-fixture' | Set-Content -LiteralPath (Join-Path $fixture 'dxgi.dll')
Expect-NRFailure '*dxgi.dll proxy*'
Remove-Item -LiteralPath (Join-Path $fixture 'dxgi.dll')
$nrPath = Join-Path $fixture 'nvngx_dlssnr.dll'
[IO.File]::WriteAllBytes($nrPath, [byte[]]@())
Expect-NRFailure '*missing: nvngx_dlssnr.dll*'
'local-component-text-fixture' | Set-Content -LiteralPath $nrPath
'different-sdk-fixture' | Set-Content -LiteralPath (Join-Path $fixture 'sl.common.dll')
Expect-NRFailure '*differs from the selected build*'
'sdk-text-fixture' | Set-Content -LiteralPath (Join-Path $fixture 'sl.common.dll')
$badConfig = $config.Replace('NeuralUplift=0', "NeuralUplift=0`r`nNeuralUplift=1")
[IO.File]::WriteAllText($ini, $badConfig)
Expect-NRFailure '*Duplicate NR setting*'
[IO.File]::WriteAllText($ini, $config)
& $launcher -RepoRoot $fixture -Profile NR -PrepareOnly
if ((Get-FileHash -LiteralPath (Join-Path $fixture 'neuralDoom.exe')).Hash -ne $manifest.sha256) { throw 'NR selected a stale engine.' }
$prepared = [IO.File]::ReadAllText($ini)
if ($prepared -ne $config.Replace('NeuralUplift=0', 'NeuralUplift=1').Replace('NREnableUpscaling=1', 'NREnableUpscaling=0')) {
    throw 'NR configuration changed unrelated tuning or did not disable upscaling.'
}
$saved = Get-Content -LiteralPath (Join-Path $fixture 'captures/dogfood/base/neural_dogfood.cfg') -Raw
if ($saved -notmatch '(?m)^unbind F6\r?$' -or $saved -notmatch '(?m)^bind F4 "toggle r_rayTracedGI; neuralHistoryReset"\r?$') { throw 'F6 conflicts with ray-lighting controls.' }
foreach ($name in $before.Keys | Where-Object { $_ -notin @('neuralDoom.exe', 'reshade.ini') }) {
    if ((Get-FileHash -LiteralPath (Join-Path $fixture $name)).Hash -ne $before[$name]) { throw "Preparation changed runtime component $name" }
}
if ([IO.File]::ReadAllText((Join-Path $fixture 'captures/dogfood/nr-backup/reshade.ini')) -ne $config) { throw 'NR configuration backup differs.' }
Write-Host 'PASS: NR read-only validation, proxy/missing/mismatched/duplicate rejection, exact engine staging, full resolution, tuning preservation and F6/F4 separation. No game or runtime loaded.'

# Preparation must retain a pending migration until an actual successful session.
$marker = Join-Path $fixture 'captures/dogfood/settings-doom-contrast-v1.applied'
if (Test-Path -LiteralPath $marker) { throw 'Preparation acknowledged an unplayed settings migration.' }
foreach ($line in @('set r_hdrAutoExposure 0', 'set r_hdrFixedLuminance 0.5', 'set r_forceAmbient 0.375', 'set r_rayTracedGIStrength 1.125', 'set r_rayTracedReflectionStrength 0.65')) {
    if (-not $saved.Contains($line)) { throw "Missing automatic migration command: $line" }
}
$playerConfig = Join-Path $fixture 'captures/dogfood/base/D3BFGConfig.cfg'
$playerText = "set r_hdrPeakNits 650`r`nset r_rayTracedReflectionStrength 0.42`r`n"
[IO.File]::WriteAllText($playerConfig, $playerText)
& $launcher -RepoRoot $fixture -Profile NR -PrepareOnly
$backupPath = Join-Path $fixture 'captures/dogfood/settings-before-doom-contrast-v1.cfg'
if ([IO.File]::ReadAllText($backupPath) -ne $playerText) { throw 'Migration backup did not preserve the saved config.' }
'fixture completed session' | Set-Content -LiteralPath $marker
& $launcher -RepoRoot $fixture -Profile NR -PrepareOnly
$next = Get-Content -LiteralPath (Join-Path $fixture 'captures/dogfood/base/neural_dogfood.cfg') -Raw
if ($next -match 'set r_forceAmbient|set r_hdrAutoExposure|set r_rayTracedReflectionStrength') { throw 'Completed migration overwrote later tuning.' }
if ([IO.File]::ReadAllText($playerConfig) -ne $playerText) { throw 'Preparation edited the saved config.' }
Write-Host 'PASS: automatic contrast migration, preparation retry, exact config backup, and preservation of later tuning.'
