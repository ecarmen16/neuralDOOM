[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$GamePath,
    [string]$D3HDPArchivePath,
    [switch]$SkipD3HDP,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-SetupStep {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-SetupCommand {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-SetupNative {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @(),
        [Parameter()][int[]]$SuccessExitCodes = @(0)
    )

    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($SuccessExitCodes -notcontains $exitCode) {
        throw "Command failed with exit code ${exitCode}: $FilePath $($ArgumentList -join ' ')"
    }
}

function Get-SetupFileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    $output = @(& certutil.exe -hashfile $Path SHA256)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not calculate SHA-256 for: $Path"
    }
    $hashLine = $output |
        Where-Object { ($_ -replace '\s', '') -match '^[0-9A-Fa-f]{64}$' } |
        Select-Object -First 1
    if (-not $hashLine) {
        throw "Could not parse SHA-256 for: $Path"
    }
    return ($hashLine -replace '\s', '').ToUpperInvariant()
}

function Find-SetupEngine {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Configuration = 'RelWithDebInfo'
    )

    $candidates = @(
        (Join-Path $Root 'neuralDoom.exe'),
        (Join-Path $Root "build\$Configuration\neuralDoom.exe"),
        (Join-Path $Root "build-streamline\$Configuration\neuralDoom.exe"),
        (Join-Path $Root 'RBDoom3BFG.exe'),
        (Join-Path $Root "build\$Configuration\RBDoom3BFG.exe"),
        (Join-Path $Root "build-streamline\$Configuration\RBDoom3BFG.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$d3hdpSourcePage = 'https://www.moddb.com/downloads/d3hdp-bfg-lite'
$d3hdpExpectedHash = 'E72ABB1C6C8C69FB28913D33709B298AC9553D4F52B10B0D02776BF00589BC4F'
$d3hdpFolder = Join-Path $RepoRoot 'mod_D3HDP_Lite'

Write-Host ''
Write-Host '========================================' -ForegroundColor DarkCyan
Write-Host '          neuralDoom Setup' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor DarkCyan
Write-Host 'Uses a legally owned Doom 3 BFG installation and keeps optional content local.'

if ([string]::IsNullOrWhiteSpace($GamePath)) {
    if ($NonInteractive) {
        throw '-GamePath is required with -NonInteractive.'
    }
    $GamePath = Read-Host 'Path to your Doom 3 BFG Edition folder (the folder containing base)'
}

$GamePath = $GamePath.Trim('"')
if (-not (Test-Path -LiteralPath $GamePath -PathType Container)) {
    throw "Game folder does not exist: $GamePath"
}
$GamePath = (Resolve-Path -LiteralPath $GamePath).Path
$sourceBase = if ((Split-Path -Leaf $GamePath) -ieq 'base') { $GamePath } else { Join-Path $GamePath 'base' }
if (-not (Test-Path -LiteralPath $sourceBase -PathType Container)) {
    throw "A base folder was not found under: $GamePath"
}

$retailResources = @(Get-ChildItem -LiteralPath $sourceBase -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.resources', '.resource') })
if ($retailResources.Count -eq 0) {
    throw "No Doom 3 BFG .resources files were found under: $sourceBase"
}

$destinationBase = Join-Path $RepoRoot 'base'
if (-not (Test-Path -LiteralPath $destinationBase)) {
    New-Item -ItemType Directory -Path $destinationBase | Out-Null
}
Write-SetupStep 'Copying missing files from the locally owned Doom 3 BFG installation'
& robocopy $sourceBase $destinationBase /E /XC /XN /XO /R:2 /W:1 /NFL /NDL /NP
$robocopyExit = $LASTEXITCODE
if ($robocopyExit -gt 7) {
    throw "robocopy failed with exit code $robocopyExit"
}
Write-Host "Retail data ready: $destinationBase" -ForegroundColor Green

if (-not $SkipD3HDP) {
    if ([string]::IsNullOrWhiteSpace($D3HDPArchivePath)) {
        $downloadCandidate = Join-Path (Join-Path $HOME 'Downloads') 'D3HDP_BFG_Lite.zip'
        if (Test-Path -LiteralPath $downloadCandidate) {
            $D3HDPArchivePath = $downloadCandidate
        } elseif (-not $NonInteractive) {
            Write-Host "Optional D3HDP source: $d3hdpSourcePage"
            $D3HDPArchivePath = Read-Host 'D3HDP_BFG_Lite.zip path, or press Enter to skip'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($D3HDPArchivePath)) {
        $D3HDPArchivePath = $D3HDPArchivePath.Trim('"')
        if (-not (Test-Path -LiteralPath $D3HDPArchivePath -PathType Leaf)) {
            throw "D3HDP archive does not exist: $D3HDPArchivePath"
        }
        $D3HDPArchivePath = (Resolve-Path -LiteralPath $D3HDPArchivePath).Path
        $archiveHash = Get-SetupFileSha256 -Path $D3HDPArchivePath
        if ($archiveHash -ne $d3hdpExpectedHash) {
            throw "D3HDP archive hash is not the verified release. Expected $d3hdpExpectedHash, received $archiveHash."
        }

        if (Test-Path -LiteralPath $d3hdpFolder) {
            Write-SetupStep 'D3HDP BFG Lite is already installed; leaving it unchanged'
        } else {
            $entries = @(& tar -tf $D3HDPArchivePath)
            if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) {
                throw 'Could not inspect the D3HDP archive.'
            }
            $unsafeEntries = @($entries | Where-Object {
                $_ -match '(^|/)\.\.(/|$)' -or
                $_ -match '^[A-Za-z]:' -or
                $_ -match '^/' -or
                ($_ -ne 'Readme.txt' -and $_ -notlike 'mod_D3HDP_Lite/*')
            })
            if ($unsafeEntries.Count -gt 0) {
                throw "D3HDP archive contains an unexpected path: $($unsafeEntries[0])"
            }

            Write-SetupStep 'Extracting verified D3HDP BFG Lite into its isolated mod folder'
            if (Test-SetupCommand '7z') {
                Invoke-SetupNative '7z' @('x', '-y', "-o$RepoRoot", $D3HDPArchivePath, 'mod_D3HDP_Lite\*')
            } else {
                Invoke-SetupNative 'tar' @('-xf', $D3HDPArchivePath, '-C', $RepoRoot, 'mod_D3HDP_Lite')
            }
        }
    }
}

Write-SetupStep 'Checking neuralDoom engine and optional local runtime components'
$engine = Find-SetupEngine -Root $RepoRoot
if ($engine) {
    Write-Host "[present] Engine: $engine" -ForegroundColor Green
} else {
    Write-Host '[missing] Build neuralDoom with the scripts in tools\neural-rendering.' -ForegroundColor Yellow
}

$runtimeFiles = @(
    'sl.interposer.dll',
    'sl.common.dll',
    'sl.dlss.dll',
    'nvngx_dlss.dll',
    'dxgi.dll',
    'neuraldoom-reshade64.dll',
    'renodx-dlss5.addon64',
    'nvngx_dlssnr.dll'
)
foreach ($runtimeFile in $runtimeFiles) {
    $present = Test-Path -LiteralPath (Join-Path $RepoRoot $runtimeFile)
    $color = if ($present) { 'Green' } else { 'Yellow' }
    $state = if ($present) { 'present' } else { 'missing' }
    Write-Host "[$state] $runtimeFile" -ForegroundColor $color
}

$proxyReShadePresent = Test-Path -LiteralPath (Join-Path $RepoRoot 'dxgi.dll')
$embeddedReShadePresent = Test-Path -LiteralPath (Join-Path $RepoRoot 'neuraldoom-reshade64.dll')
if ($proxyReShadePresent -and $embeddedReShadePresent) {
    Write-Warning 'Both ReShade startup modes are present. Keep exactly one of dxgi.dll or neuraldoom-reshade64.dll.'
} elseif ($embeddedReShadePresent) {
    Write-Host '[mode] ReShade will be loaded explicitly by neuralDoom.' -ForegroundColor Green
} elseif ($proxyReShadePresent) {
    Write-Host '[mode] ReShade is currently installed as a DXGI proxy. Run Switch-NeuralDoom-ReShadeMode.cmd to use embedded startup.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'neuralDoom never downloads or copies an experimental NVIDIA Neural Rendering runtime.' -ForegroundColor Yellow
Write-Host 'Optional runtime installation remains a documented manual step until its distribution terms are verified.' -ForegroundColor Yellow
Write-Host ''
if (Test-Path -LiteralPath $d3hdpFolder) {
    if ($embeddedReShadePresent -and -not $proxyReShadePresent) {
        Write-Host 'Ready: double-click Launch-NeuralDoom-EmbeddedNR-D3HDP.cmd' -ForegroundColor Green
    } else {
        Write-Host 'Ready: double-click Launch-NeuralDoom-D3HDP.cmd' -ForegroundColor Green
    }
} else {
    if ($embeddedReShadePresent -and -not $proxyReShadePresent) {
        Write-Host 'Ready: double-click Launch-NeuralDoom-EmbeddedNR.cmd' -ForegroundColor Green
    } else {
        Write-Host 'Ready: double-click Launch-NeuralDoom.cmd' -ForegroundColor Green
    }
}
