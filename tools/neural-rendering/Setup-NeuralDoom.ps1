[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$GamePath,
    [string]$D3HDPArchivePath,
    [string]$D3HDPArchiveUrl,
    [string]$NRRuntimePath,
    [string]$NRRuntimeUrl,
    [switch]$SkipD3HDP,
    [switch]$SkipNRRuntime,
    [switch]$ForceNRRuntime,
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

function Get-SetupFileMd5 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash.ToUpperInvariant()
}

function Select-SetupFolder {
    param(
        [Parameter(Mandatory)][string]$Description,
        [string]$InitialDirectory
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $Description
        $dialog.ShowNewFolderButton = $false
        if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and
            (Test-Path -LiteralPath $InitialDirectory -PathType Container)) {
            $dialog.SelectedPath = $InitialDirectory
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
    } catch {
        Write-Verbose "Folder picker unavailable: $($_.Exception.Message)"
    }
    return $null
}

function Select-SetupFile {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Filter,
        [string]$InitialDirectory
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = $Title
        $dialog.Filter = $Filter
        $dialog.CheckFileExists = $true
        $dialog.Multiselect = $false
        if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and
            (Test-Path -LiteralPath $InitialDirectory -PathType Container)) {
            $dialog.InitialDirectory = $InitialDirectory
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
    } catch {
        Write-Verbose "File picker unavailable: $($_.Exception.Message)"
    }
    return $null
}

function Invoke-SetupDownload {
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory)][string]$Destination
    )

    if ($Uri.Scheme -ne 'https') {
        throw "Only HTTPS downloads are accepted: $Uri"
    }

    $destinationDirectory = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory | Out-Null
    }

    $partialPath = "$Destination.partial"
    if (Test-Path -LiteralPath $partialPath) {
        Remove-Item -LiteralPath $partialPath -Force
    }

    try {
        Write-Host "Downloading $Uri"
        $oldProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Uri -OutFile $partialPath -MaximumRedirection 10 -UseBasicParsing -Headers @{
            'User-Agent' = 'neuralDoom-Setup/1.0'
        }
        Move-Item -LiteralPath $partialPath -Destination $Destination -Force
    } finally {
        $ProgressPreference = $oldProgressPreference
        if (Test-Path -LiteralPath $partialPath) {
            Remove-Item -LiteralPath $partialPath -Force
        }
    }

    return $Destination
}

function Resolve-SetupModDbArchive {
    param(
        [Parameter(Mandatory)][uri]$StartUri,
        [Parameter(Mandatory)][string]$Destination
    )

    Invoke-SetupDownload -Uri $StartUri -Destination $Destination | Out-Null
    & tar -tf $Destination *> $null
    if ($LASTEXITCODE -eq 0) {
        return $Destination
    }

    $landingHtml = Get-Content -LiteralPath $Destination -Raw
    $mirrorMatch = [regex]::Match(
        $landingHtml,
        '(?i)href=["''][^"'']*(?<path>/downloads/mirror/265648/[^"'']+)["'']'
    )
    if (-not $mirrorMatch.Success) {
        throw "ModDB returned a landing page without a recognized D3HDP mirror link. Open $StartUri in a browser or select an existing archive."
    }

    $mirrorPath = [System.Net.WebUtility]::HtmlDecode($mirrorMatch.Groups['path'].Value)
    $mirrorUri = [uri]::new($StartUri, $mirrorPath)
    Invoke-SetupDownload -Uri $mirrorUri -Destination $Destination | Out-Null
    return $Destination
}

function Test-SetupD3HDPArchive {
    param([Parameter(Mandatory)][string]$Path)

    $file = Get-Item -LiteralPath $Path
    $sha256 = Get-SetupFileSha256 -Path $Path
    if ($file.Length -eq 2143217579 -and
        $sha256 -eq 'E72ABB1C6C8C69FB28913D33709B298AC9553D4F52B10B0D02776BF00589BC4F') {
        return $true
    }

    $md5 = Get-SetupFileMd5 -Path $Path
    if ($file.Length -eq 2143408902 -and $md5 -eq '1288283E5B0116EEA38BE993DA423725') {
        return $true
    }

    throw "D3HDP archive is not a recognized release. Size $($file.Length), SHA-256 $sha256, MD5 $md5."
}

function Install-SetupNRRuntime {
    param(
        [string]$SourcePath,
        [string]$SourceUrl,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$CacheDirectory
    )

    if (-not [string]::IsNullOrWhiteSpace($SourcePath) -and
        -not [string]::IsNullOrWhiteSpace($SourceUrl)) {
        throw 'Specify only one of -NRRuntimePath or -NRRuntimeUrl.'
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceUrl)) {
        $cachedRuntime = Join-Path $CacheDirectory 'nvngx_dlssnr.dll'
        Invoke-SetupDownload -Uri ([uri]$SourceUrl) -Destination $cachedRuntime | Out-Null
        $SourcePath = $cachedRuntime
    }

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return $false
    }

    $SourcePath = $SourcePath.Trim('"')
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "DLSS Neural Rendering runtime does not exist: $SourcePath"
    }
    $SourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
    $runtimeFile = Get-Item -LiteralPath $SourcePath
    if ($runtimeFile.Length -lt 1048576) {
        throw "The selected runtime is unexpectedly small ($($runtimeFile.Length) bytes): $SourcePath"
    }
    $headerBytes = if ($PSVersionTable.PSVersion.Major -ge 6) {
        @(Get-Content -LiteralPath $SourcePath -AsByteStream -TotalCount 2)
    } else {
        @(Get-Content -LiteralPath $SourcePath -Encoding Byte -TotalCount 2)
    }
    if ($headerBytes.Count -ne 2 -or $headerBytes[0] -ne 77 -or $headerBytes[1] -ne 90) {
        throw "The selected runtime is not a Windows PE DLL: $SourcePath"
    }

    if ($SourcePath -ne $Destination) {
        Copy-Item -LiteralPath $SourcePath -Destination $Destination -Force
    }

    $runtimeHash = Get-SetupFileSha256 -Path $Destination
    Write-Host "[installed] nvngx_dlssnr.dll ($runtimeHash)" -ForegroundColor Green
    $signature = Get-AuthenticodeSignature -LiteralPath $Destination
    if ($signature.SignerCertificate) {
        Write-Host "[signature] $($signature.Status): $($signature.SignerCertificate.Subject)"
    } else {
        Write-Host "[signature] $($signature.Status)" -ForegroundColor Yellow
    }
    return $true
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

$d3hdpSourcePage = 'https://www.moddb.com/mods/d3hdp-bfg-lite/downloads/d3hdp-bfg-lite'
if ([string]::IsNullOrWhiteSpace($D3HDPArchiveUrl)) {
    $D3HDPArchiveUrl = 'https://www.moddb.com/downloads/start/265648'
}
$cacheDirectory = Join-Path $RepoRoot '.neuraldoom-cache'
$d3hdpFolder = Join-Path $RepoRoot 'mod_D3HDP_Lite'
$nrRuntimeDestination = Join-Path $RepoRoot 'nvngx_dlssnr.dll'

Write-Host ''
Write-Host '========================================' -ForegroundColor DarkCyan
Write-Host '          neuralDoom Setup' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor DarkCyan
Write-Host 'Uses a legally owned Doom 3 BFG installation and keeps optional content local.'

if ([string]::IsNullOrWhiteSpace($GamePath)) {
    if ($NonInteractive) {
        throw '-GamePath is required with -NonInteractive.'
    }
    Write-Host 'Select your Doom 3 BFG Edition folder (the folder containing base).'
    $GamePath = Select-SetupFolder -Description 'Select Doom 3 BFG Edition' -InitialDirectory 'C:\Program Files (x86)\Steam\steamapps\common'
    if ([string]::IsNullOrWhiteSpace($GamePath)) {
        $GamePath = Read-Host 'Doom 3 BFG Edition folder'
    }
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

if (-not $SkipD3HDP -and (Test-Path -LiteralPath $d3hdpFolder -PathType Container)) {
    Write-SetupStep 'D3HDP BFG Lite is already installed; leaving it unchanged'
} elseif (-not $SkipD3HDP) {
    if ([string]::IsNullOrWhiteSpace($D3HDPArchivePath)) {
        $userProfile = [Environment]::GetFolderPath('UserProfile')
        $downloadCandidate = Join-Path (Join-Path $userProfile 'Downloads') 'D3HDP_BFG_Lite.zip'
        if (Test-Path -LiteralPath $downloadCandidate) {
            $D3HDPArchivePath = $downloadCandidate
        } elseif (-not $NonInteractive) {
            Write-Host "Optional HD texture pack: $d3hdpSourcePage"
            $d3hdpChoice = (Read-Host 'Download D3HDP [D], browse for an archive [B], or skip [S] (default D)').Trim()
            if ([string]::IsNullOrWhiteSpace($d3hdpChoice) -or $d3hdpChoice -ieq 'D') {
                $D3HDPArchivePath = Join-Path $cacheDirectory 'D3HDP_BFG_Lite.zip'
                if (-not (Test-Path -LiteralPath $D3HDPArchivePath -PathType Leaf)) {
                    Write-SetupStep 'Downloading D3HDP BFG Lite from ModDB'
                    Resolve-SetupModDbArchive -StartUri ([uri]$D3HDPArchiveUrl) -Destination $D3HDPArchivePath | Out-Null
                }
            } elseif ($d3hdpChoice -ieq 'B') {
                $D3HDPArchivePath = Select-SetupFile -Title 'Select D3HDP_BFG_Lite.zip' -Filter 'ZIP archives (*.zip)|*.zip|All files (*.*)|*.*' -InitialDirectory (Join-Path $userProfile 'Downloads')
                if ([string]::IsNullOrWhiteSpace($D3HDPArchivePath)) {
                    $D3HDPArchivePath = Read-Host 'D3HDP_BFG_Lite.zip path, or press Enter to skip'
                }
            }
        } elseif (-not [string]::IsNullOrWhiteSpace($D3HDPArchiveUrl)) {
            $D3HDPArchivePath = Join-Path $cacheDirectory 'D3HDP_BFG_Lite.zip'
            if (-not (Test-Path -LiteralPath $D3HDPArchivePath -PathType Leaf)) {
                Resolve-SetupModDbArchive -StartUri ([uri]$D3HDPArchiveUrl) -Destination $D3HDPArchivePath | Out-Null
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($D3HDPArchivePath)) {
        $D3HDPArchivePath = $D3HDPArchivePath.Trim('"')
        if (-not (Test-Path -LiteralPath $D3HDPArchivePath -PathType Leaf)) {
            throw "D3HDP archive does not exist: $D3HDPArchivePath"
        }
        $D3HDPArchivePath = (Resolve-Path -LiteralPath $D3HDPArchivePath).Path
        Test-SetupD3HDPArchive -Path $D3HDPArchivePath | Out-Null

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

if (-not $SkipNRRuntime -and
    ($ForceNRRuntime -or -not (Test-Path -LiteralPath $nrRuntimeDestination -PathType Leaf))) {
    if ([string]::IsNullOrWhiteSpace($NRRuntimePath) -and
        [string]::IsNullOrWhiteSpace($NRRuntimeUrl) -and
        -not $NonInteractive) {
        Write-Host ''
        Write-Host 'DLSS Neural Rendering runtime' -ForegroundColor Cyan
        $nrChoice = (Read-Host 'Browse for nvngx_dlssnr.dll [B], download from a URL [U], or skip [S] (default B)').Trim()
        if ([string]::IsNullOrWhiteSpace($nrChoice) -or $nrChoice -ieq 'B') {
            $NRRuntimePath = Select-SetupFile -Title 'Select nvngx_dlssnr.dll' -Filter 'DLSS Neural Rendering runtime (nvngx_dlssnr.dll)|nvngx_dlssnr.dll|DLL files (*.dll)|*.dll' -InitialDirectory (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads')
            if ([string]::IsNullOrWhiteSpace($NRRuntimePath)) {
                $NRRuntimePath = Read-Host 'nvngx_dlssnr.dll path, or press Enter to skip'
            }
        } elseif ($nrChoice -ieq 'U') {
            $NRRuntimeUrl = Read-Host 'HTTPS URL for nvngx_dlssnr.dll'
        }
    }

    Install-SetupNRRuntime -SourcePath $NRRuntimePath -SourceUrl $NRRuntimeUrl -Destination $nrRuntimeDestination -CacheDirectory $cacheDirectory | Out-Null
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
if (Test-Path -LiteralPath $nrRuntimeDestination -PathType Leaf) {
    Write-Host 'DLSS Neural Rendering runtime is staged locally and ignored by Git.' -ForegroundColor Green
} else {
    Write-Host 'DLSS Neural Rendering runtime was skipped; rerun setup to browse for it or supply an HTTPS URL.' -ForegroundColor Yellow
}
Write-Host 'Third-party archives and runtime DLLs remain local installation inputs; they are not part of the source repository.' -ForegroundColor DarkGray
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
