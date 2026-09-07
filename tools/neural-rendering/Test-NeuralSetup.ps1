[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Common.ps1')
$repo = Resolve-NeuralRepoRoot
$fixture = Join-Path $repo ('captures/neural/setup-fixture-' + [guid]::NewGuid().ToString('N'))
$build = Join-Path $fixture 'build-rt'
$base = Join-Path $fixture 'base'
$shaderRoot = Join-Path $base 'renderprogs2/dxil/rt'
New-Item -ItemType Directory -Path $build, $shaderRoot, (Join-Path $base 'maps') -Force | Out-Null
# Text fixtures only. ValidateOnly must never execute these files or access the GPU.
$exact = Join-Path $build 'fixture.exe'
'exact-build-fixture' | Set-Content -LiteralPath $exact
'stale-root-fixture' | Set-Content -LiteralPath (Join-Path $fixture 'neuralDoom.exe')
$exact | Set-Content -LiteralPath (Join-Path $build 'neuraldoom-artifact-RelWithDebInfo.txt')
$manifestPath = Join-Path $build 'neuraldoom-build-RelWithDebInfo.json'
$manifest = @{
    sha256 = (Get-FileHash -LiteralPath $exact).Hash; executable = $exact; configuration = 'RelWithDebInfo';
    commit = 'fixture'; dirty = $false; features = @{ dx12 = 'ON'; rayTracing = 'ON'; streamline = 'OFF' }
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath
'retail-data-fixture' | Set-Content -LiteralPath (Join-Path $base 'maps/mars_city2.resources')
$lighting = Join-Path $base '_rbdoom_global_illumination_data.pk4'
'lighting-inventory-fixture' | Set-Content -LiteralPath $lighting
foreach ($shader in @('ray_query', 'ambient_occlusion', 'contact_shadows', 'visibility_debug', 'material_atlas', 'diffuse_bounce', 'bounce_composite')) {
    'shader-fixture' | Set-Content -LiteralPath (Join-Path $shaderRoot "$shader.cs.dxil")
}
$setup = Join-Path $PSScriptRoot 'Setup-NeuralDoom.ps1'
& $setup -RepoRoot $fixture -ValidateOnly
if (Test-Path -LiteralPath (Join-Path $fixture 'captures/dogfood')) { throw 'Read-only readiness check created player settings.' }

function Expect-SetupFailure {
    param([Parameter(Mandatory)][string]$Pattern)
    $caught = $false
    try { & $setup -RepoRoot $fixture -ValidateOnly } catch {
        if ($_.Exception.Message -notlike $Pattern) { throw }
        $caught = $true
    }
    if (-not $caught) { throw "Setup falsely reported READY: expected $Pattern" }
}
# Missing build output must not fall back to the unrelated root executable.
$missing = Join-Path $build 'missing.exe'
$missing | Set-Content -LiteralPath (Join-Path $build 'neuraldoom-artifact-RelWithDebInfo.txt')
Expect-SetupFailure '*configured executable is missing*'
$exact | Set-Content -LiteralPath (Join-Path $build 'neuraldoom-artifact-RelWithDebInfo.txt')
'changed-build-fixture' | Set-Content -LiteralPath $exact
Expect-SetupFailure '*does not match its build manifest*'
'exact-build-fixture' | Set-Content -LiteralPath $exact
$shaderPath = Join-Path $shaderRoot 'diffuse_bounce.cs.dxil'
[IO.File]::WriteAllBytes($shaderPath, [byte[]]@())
Expect-SetupFailure '*Missing RTX shader: diffuse_bounce*'
'shader-fixture' | Set-Content -LiteralPath $shaderPath
[IO.File]::WriteAllBytes($lighting, [byte[]]@())
Expect-SetupFailure '*Full lighting data is missing*'
Write-Host 'PASS: offline/read-only setup, exact executable identity, stale-root rejection, missing shader and missing lighting detection. No game launched.'
Write-Host "Fixtures: $fixture"
