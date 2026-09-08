[CmdletBinding()]
param([Parameter(Mandatory)][string]$ArchiveCache)
. (Join-Path $PSScriptRoot 'Setup-NeuralComponents.ps1')
$ArchiveCache = (Resolve-Path -LiteralPath $ArchiveCache).Path
$fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('../../captures/neural/components-' + [guid]::NewGuid().ToString('N'))))
$build = Join-Path $fixture 'build-streamline/Release'
New-Item -ItemType Directory -Path $build -Force | Out-Null
'fixture-engine-not-loaded' | Set-Content -LiteralPath (Join-Path $build 'neuralDoom.exe')
$script:downloads = @()
# Offline integration: still verify each real archive against tracked pins.
function Get-SetupDownload {
    param($Uri, $Destination, $Sha256, $Bytes, $Headers)
    $script:downloads += $Uri
    $path = Join-Path $ArchiveCache (Split-Path -Leaf $Destination)
    if ((Get-FileHash -LiteralPath $path).Hash -ne $Sha256 -or (Get-Item -LiteralPath $path).Length -ne $Bytes) { throw 'Fixture archive does not match release pin.' }
    return $path
}
Install-SetupNeuralComponents -RepoRoot $fixture -Profile Native
if ($script:downloads.Count) { throw 'Native mode acquired a neural component.' }
Install-SetupNeuralComponents -RepoRoot $fixture -Profile NR
if ($script:downloads.Count -ne 5) { throw 'NR did not obtain all five required components.' }
if (Test-Path -LiteralPath (Join-Path $fixture 'dxgi.dll')) { throw 'Setup created a DXGI proxy.' }
$ini = Join-Path $fixture 'reshade.ini'
$text = [IO.File]::ReadAllText($ini)
foreach ($key in @('NeuralUplift=1','NREnableUpscaling=0','EnableHooks=1','NRToggleKey=117','NRScreenshotKey=124')) { if (-not $text.Contains($key)) { throw "Missing NR contract: $key" } }
[IO.File]::WriteAllText($ini, $text + "NRIntensity=0.75`r`n")
$script:downloads = @()
Install-SetupNeuralComponents -RepoRoot $fixture -Profile NR -DlssDllPath (Join-Path $ArchiveCache 'nvngx_dlss.dll') -NRDllPath (Join-Path $fixture 'nvngx_dlssnr.dll')
if ($script:downloads.Count -ne 3 -or [IO.File]::ReadAllText($ini) -notmatch 'NRIntensity=0.75') { throw 'Local DLL selection downloaded replacements or lost tuning.' }
$caught = $false
try { Test-SetupNvidiaDll (Join-Path $build 'neuralDoom.exe') } catch { $caught = $true }
if (-not $caught) { throw 'Invalid DLL accepted.' }
$caught = $false
try { Test-SetupNvidiaDll (Join-Path $ArchiveCache 'nvngx_dlssnr.dll') -RequiredHash '6eb209e764f39872625debd6abaf45e2bb6322f6f270f781f70c059ae30b3927' } catch { $caught = $true }
if (-not $caught) { throw 'Known incompatible NR DLL accepted.' }
Write-Host 'PASS: pinned real archives, official ReShade SFX extraction, native no-download path, complete NR stack, full-resolution/F6 contract, signed local DLL selection and tuning preservation. No DLL loaded.'
