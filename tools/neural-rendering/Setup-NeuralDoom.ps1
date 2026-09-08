[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$GamePath,
    [string]$LightingPackPath,
    [string]$D3HDPArchivePath,
    [string]$D3HDPArchiveUrl,
    [string]$NRRuntimePath,
    [string]$NRRuntimeUrl,
    [ValidateSet('Native', 'DLAA')][string]$Profile = 'Native',
    [ValidateSet('Release', 'RelWithDebInfo')][string]$Configuration = 'RelWithDebInfo',
    [switch]$BuildEngine,
    [switch]$ValidateOnly,
    [switch]$IncludeLegacyNR,
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

function Test-SetupReady {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RenderingProfile
    )
    & (Join-Path $PSScriptRoot 'Start-NeuralDoom-Dogfood.ps1') -RepoRoot $Root -Profile $RenderingProfile -Configuration $Configuration -ValidateOnly
    $lighting = & (Join-Path $PSScriptRoot 'Get-NeuralLightingData.ps1') -RepoRoot $Root
    Write-Host "[lighting] $($lighting.detail)"
    if (-not $lighting.hasCandidates) {
        throw 'Full lighting data is missing. Extract base/_rbdoom_global_illumination_data.pk4 from the official RBDOOM-3-BFG 1.6.0 release, then rerun setup with -LightingPackPath pointing to that file. See docs/neural-rendering/PROBE_LIGHTING.md.'
    }
    Write-Host 'READY: Launch-NeuralDoom.cmd for saved settings; Launch-NeuralDoom-RTX.cmd seeds missing RTX preferences. Internal Release ZIP: Play-InternalTest.cmd.' -ForegroundColor Green
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if ($IncludeLegacyNR -or $NRRuntimePath -or $NRRuntimeUrl -or $ForceNRRuntime) { throw 'These legacy NR options were replaced by the complete internal installer: select its NR profile and automatic download or local DLL options.' }
if ($ValidateOnly) {
    if ($BuildEngine) { throw '-ValidateOnly does not build or install files; omit -BuildEngine.' }
    Test-SetupReady -Root $RepoRoot -RenderingProfile $Profile
    return
}
if ($NonInteractive -and -not $D3HDPArchivePath -and -not $D3HDPArchiveUrl) { $SkipD3HDP = $true }

$d3hdpSourcePage = 'https://www.moddb.com/mods/d3hdp-bfg-lite/downloads/d3hdp-bfg-lite'
if ([string]::IsNullOrWhiteSpace($D3HDPArchiveUrl)) {
    $D3HDPArchiveUrl = 'https://www.moddb.com/downloads/start/265648'
}
$cacheDirectory = Join-Path $RepoRoot '.neuraldoom-cache'
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
if ([IO.Path]::GetFullPath($sourceBase).TrimEnd('\') -ine [IO.Path]::GetFullPath($destinationBase).TrimEnd('\')) {
    & robocopy $sourceBase $destinationBase /E /XC /XN /XO /XJ /R:2 /W:1 /NFL /NDL /NP /NJH /NJS
    $robocopyExit = $LASTEXITCODE
    if ($robocopyExit -gt 7) { throw "robocopy failed with exit code $robocopyExit" }
}
Write-Host "Retail data ready: $destinationBase" -ForegroundColor Green

if ($LightingPackPath) {
    $LightingPackPath = (Resolve-Path -LiteralPath $LightingPackPath).Path
    $lightingDestination = Join-Path $destinationBase '_rbdoom_global_illumination_data.pk4'
    if ((Get-Item -LiteralPath $LightingPackPath).Length -ne 1478656988 -or
        (Get-SetupFileSha256 -Path $LightingPackPath) -ne 'D83D1D1D4F9F72D4DC1B8F7870BC0C379ADEEE5A405C2AB1FE4308851FBB303F') {
        throw 'Lighting pack does not match the locally verified official 1.6.0 pack documented in PROBE_LIGHTING.md.'
    }
    if ($LightingPackPath -ine $lightingDestination) {
        if (Test-Path -LiteralPath $lightingDestination) {
            if ((Get-SetupFileSha256 -Path $lightingDestination) -ne (Get-SetupFileSha256 -Path $LightingPackPath)) { throw 'A different lighting pack is already installed; preserving it.' }
        } else { Copy-Item -LiteralPath $LightingPackPath -Destination $lightingDestination }
    }
    Write-Host '[lighting] Verified RBDOOM 1.6.0 lighting pack installed locally.' -ForegroundColor Green
}

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

if ($BuildEngine) {
    $buildDirectory = Join-Path $RepoRoot $(if ($Profile -eq 'DLAA') { 'build-streamline' } else { 'build-rt' })
    if ($Profile -eq 'DLAA' -and -not (Test-Path -LiteralPath (Join-Path $buildDirectory 'CMakeCache.txt'))) {
        throw 'Configure the optional official Streamline SDK build first, or use -Profile Native.'
    }
    Write-SetupStep "Building $Profile with native ray tracing"
    & (Join-Path $PSScriptRoot 'Configure-RBDOOM-DX12.ps1') -RepoRoot $RepoRoot -BuildDirectory $buildDirectory -RayTracing ON
    & (Join-Path $PSScriptRoot 'Build-RBDOOM.ps1') -RepoRoot $RepoRoot -BuildDirectory $buildDirectory -Configuration $Configuration
}
Write-SetupStep 'Validating the exact native RTX build, shaders and local game installation'
Test-SetupReady -Root $RepoRoot -RenderingProfile $Profile

Write-Host 'Setup assembles local files. Retail assets, downloaded lighting/mod packs and NVIDIA runtimes are excluded from the GitHub source.'
