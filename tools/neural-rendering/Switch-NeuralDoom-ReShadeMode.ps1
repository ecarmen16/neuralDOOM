[CmdletBinding()]
param(
    [ValidateSet('Embedded', 'Proxy')]
    [string]$Mode = 'Embedded',

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'

$proxyPath = Join-Path $RepoRoot 'dxgi.dll'
$embeddedPath = Join-Path $RepoRoot 'neuraldoom-reshade64.dll'
$configPath = Join-Path $RepoRoot 'reshade.ini'
$addonPath = Join-Path $RepoRoot 'renodx-dlss5.addon64'
$nrRuntimePath = Join-Path $RepoRoot 'nvngx_dlssnr.dll'

if (Get-Process -Name 'NeuralDoom', 'RBDoom3BFG' -ErrorAction SilentlyContinue) {
    throw 'Close NeuralDoom before switching ReShade startup modes.'
}

if ($Mode -eq 'Embedded') {
    if ((Test-Path -LiteralPath $proxyPath) -and (Test-Path -LiteralPath $embeddedPath)) {
        throw 'Both dxgi.dll and neuraldoom-reshade64.dll exist. Remove the duplicate manually after verifying which file is current.'
    }
    if (Test-Path -LiteralPath $proxyPath) {
        Move-Item -LiteralPath $proxyPath -Destination $embeddedPath
        Write-Host 'Moved dxgi.dll to neuraldoom-reshade64.dll.' -ForegroundColor Green
    } elseif (-not (Test-Path -LiteralPath $embeddedPath)) {
        throw 'No local ReShade runtime was found. Install ReShade first, then run this switch again.'
    } else {
        Write-Host 'Embedded ReShade mode is already prepared.' -ForegroundColor Green
    }
} else {
    if ((Test-Path -LiteralPath $proxyPath) -and (Test-Path -LiteralPath $embeddedPath)) {
        throw 'Both dxgi.dll and neuraldoom-reshade64.dll exist. Remove the duplicate manually after verifying which file is current.'
    }
    if (Test-Path -LiteralPath $embeddedPath) {
        Move-Item -LiteralPath $embeddedPath -Destination $proxyPath
        Write-Host 'Restored neuraldoom-reshade64.dll to dxgi.dll proxy mode.' -ForegroundColor Green
    } elseif (-not (Test-Path -LiteralPath $proxyPath)) {
        throw 'No local ReShade runtime was found.'
    } else {
        Write-Host 'DXGI proxy mode is already prepared.' -ForegroundColor Green
    }
}

foreach ($requiredPath in @($configPath, $addonPath, $nrRuntimePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        Write-Warning "Optional NR component is missing: $([IO.Path]::GetFileName($requiredPath))"
    }
}

Write-Host "ReShade startup mode: $Mode"
