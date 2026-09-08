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
if ($prepared -ne $config.Replace('NeuralUplift=0', 'NeuralUplift=1').Replace('NREnableUpscaling=1', 'NREnableUpscaling=0').Replace('[OTHER]', "EnableHooks=1`r`nNRToggleKey=117`r`nNRScreenshotKey=124`r`n[OTHER]")) {
    throw 'NR configuration changed unrelated tuning or did not disable upscaling.'
}
$saved = Get-Content -LiteralPath (Join-Path $fixture 'captures/dogfood/base/neural_dogfood.cfg') -Raw
if ($saved -notmatch '(?m)^neuralInstallKeys startup\r?$' -or $saved -match '(?m)^(?:un)?bind F[46]') { throw 'NR preparation bypassed safe binding migration.' }
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

# The SDK profile honors saved reconstruction; NR keeps native DLAA input.
[IO.File]::WriteAllText($playerConfig, 'set r_neuralReconstructionMode "0"' + "`r`n")
$preparedTAA = (& $launcher -RepoRoot $fixture -Profile DLAA -PrepareOnly 6>&1 | Out-String)
if ($preparedTAA -notmatch 'Reconstruction: Native TAA') { throw 'DLAA profile ignored saved TAA preference.' }
$preparedNR = (& $launcher -RepoRoot $fixture -Profile NR -PrepareOnly 6>&1 | Out-String)
if ($preparedNR -notmatch 'Reconstruction: DLAA') { throw 'NR no longer has DLAA input.' }
[IO.File]::WriteAllText($playerConfig, 'set r_neuralReconstructionMode "1"' + "`r`n")
$preparedDLAA = (& $launcher -RepoRoot $fixture -Profile DLAA -PrepareOnly 6>&1 | Out-String)
if ($preparedDLAA -notmatch 'Reconstruction: DLAA') { throw 'DLAA preference was not restored.' }
Write-Host 'PASS: saved TAA/DLAA selection, NR input isolation, and no process launch.'
foreach ($mode in @(2,3,4)) {
    [IO.File]::WriteAllText($playerConfig, "set r_neuralReconstructionMode $mode`r`n")
    $preparedDLSS = (& $launcher -RepoRoot $fixture -Profile DLAA -PrepareOnly 6>&1 | Out-String)
    $expected = @('Quality','Balanced','Performance')[$mode - 2]
    if ($preparedDLSS -notmatch "Reconstruction: DLSS $expected") { throw 'Saved DLSS preset was not restored.' }
    $preparedNR = (& $launcher -RepoRoot $fixture -Profile NR -PrepareOnly 6>&1 | Out-String)
    if ($preparedNR -notmatch 'Reconstruction: DLAA') { throw 'NR inherited a reduced-resolution DLSS preset.' }
}
Write-Host 'PASS: saved DLSS Quality/Balanced/Performance presets survive preparation.'
foreach ($mode in 0..4) {
    $name = @('TAA','DLAA','Quality','Balanced','Performance')[$mode]
    $null = & $launcher -RepoRoot $fixture -Profile DLAA -Reconstruction $name -PrepareOnly 6>$null
    $generated = Get-Content -LiteralPath (Join-Path $fixture 'captures/dogfood/base/neural_dogfood.cfg') -Raw
    if ($generated -notmatch "(?m)^set r_neuralReconstructionMode $mode\r?$") { throw 'Launch quality was not persisted for the menu.' }
}
Write-Host 'PASS: explicit launch quality selections are written to the game session config.'

# Inspect the actual prepared argv without starting a process.
$disabledRays = "set r_rayTracedAO 0`nset r_rayTracedContactShadows 0`nset r_rayTracedGI 0`nset r_rayTracedReflections 0`n"
[IO.File]::WriteAllText($playerConfig, $disabledRays)
$savedRayArgs = & {
    . $launcher -RepoRoot $fixture -Profile DLAA -RayTracedAO -RayTracedContactShadows -RayTracedGI -RayTracedReflections -PrepareOnly 6>$null
    $launchArgs -join ' '
}
if ($savedRayArgs -match '\+set r_rayTraced(?:AO|ContactShadows|GI|Reflections) 1') { throw 'Launcher overrode saved RTX disable preferences.' }
[IO.File]::WriteAllText($playerConfig, '')
$seedRayArgs = & {
    . $launcher -RepoRoot $fixture -Profile DLAA -RayTracedAO -RayTracedContactShadows -RayTracedGI -RayTracedReflections -PrepareOnly 6>$null
    $launchArgs -join ' '
}
foreach ($ray in @('AO', 'ContactShadows', 'GI', 'Reflections')) {
    if ($seedRayArgs -notmatch ( '\+set r_rayTraced' + $ray + ' 1' )) { throw "Missing first-use RTX seed: $ray" }
}
Write-Host 'PASS: saved RTX off choices survive relaunch; missing preferences are seeded.'

[IO.File]::WriteAllText($playerConfig, 'set r_neuralLaunchProfile "1"' + "`n")
$menuProfile = (& $launcher -RepoRoot $fixture -PrepareOnly 6>&1 | Out-String)
if ($menuProfile -notmatch 'Profile:    DLAA') { throw 'Menu launch preference was not honored.' }
Write-Host 'PASS: menu-selected launch profile requires no launcher prompt.'

'{"profile":"Native"}' | Set-Content -LiteralPath (Join-Path $fixture '.neuraldoom-install.json')
[IO.File]::WriteAllText($playerConfig, 'set r_neuralLaunchProfile "-1"' + "`n")
$promptCalls = New-Object 'Collections.Generic.List[string]'
function Read-Host { $promptCalls.Add('prompt'); return '2' }
$askProfile = (& $launcher -RepoRoot $fixture -PrepareOnly 6>&1 | Out-String)
$askConfig = Get-Content -LiteralPath (Join-Path $fixture 'captures/dogfood/base/neural_dogfood.cfg') -Raw
if ($promptCalls.Count -ne 1 -or $askProfile -notmatch 'Profile:    DLAA' -or $askConfig -notmatch '(?m)^set r_neuralLaunchProfile -1\r?$') { throw 'Ask at launch was overridden or not preserved.' }
'NR' | Set-Content -LiteralPath (Join-Path $fixture 'captures/dogfood/installed-profile.pending')
$pendingProfile = (& $launcher -RepoRoot $fixture -PrepareOnly 6>&1 | Out-String)
if ($promptCalls.Count -ne 1 -or $pendingProfile -notmatch 'Profile:    NR') { throw 'Pending installer selection did not take precedence.' }
Write-Host 'PASS: Ask at launch survives the installer default and preserves prompting; pending setup selection takes precedence.'
