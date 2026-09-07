# Download supporting files from their original publishers into a local cache.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-SetupStatus {
    param([string]$Message)
    if ($env:NEURALDOOM_SETUP_CANCEL_FILE -and (Test-Path -LiteralPath $env:NEURALDOOM_SETUP_CANCEL_FILE)) { throw 'Setup cancelled. Verified downloads are retained for retry.' }
    Write-Host "@@SETUP|$Message"
}

function Get-SetupDownload {
    param([string]$Uri, [string]$Destination, [string]$Sha256, [long]$Bytes = 0)
    if ([uri]::new($Uri).Scheme -ne 'https') { throw 'Setup downloads require HTTPS.' }
    if (Test-Path -LiteralPath $Destination) {
        if ($Sha256 -and (Get-FileHash -LiteralPath $Destination).Hash -eq $Sha256 -and
            ($Bytes -eq 0 -or (Get-Item -LiteralPath $Destination).Length -eq $Bytes)) { return $Destination }
        # Never execute an unverified cached prerequisite.
        Remove-Item -LiteralPath $Destination -Force
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    $partial = "$Destination.partial"
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-SetupStatus "Downloading supporting files (attempt $attempt of 3)..."
        try {
            Write-Host "Downloading $(Split-Path -Leaf $Destination) (attempt $attempt/3)..."
            if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
            # BITS supplies transfer progress on Windows; web download is the fallback.
            try { Start-BitsTransfer -Source $Uri -Destination $partial -ErrorAction Stop }
            catch { Invoke-WebRequest -Uri $Uri -OutFile $partial -UseBasicParsing -ErrorAction Stop }
            if ($Bytes -gt 0 -and (Get-Item -LiteralPath $partial).Length -ne $Bytes) { throw 'Downloaded size does not match the pinned release.' }
            if ($Sha256 -and (Get-FileHash -LiteralPath $partial).Hash -ne $Sha256) { throw 'Downloaded SHA-256 does not match the pinned release.' }
            Move-Item -LiteralPath $partial -Destination $Destination -Force
            return $Destination
        } catch {
            if ($attempt -eq 3) { throw "Download failed: $Uri. $($_.Exception.Message) Rerun setup to retry." }
        }
    }
}

function Get-SetupLightingPack {
    param([string]$RepoRoot)
    $packHash = 'D83D1D1D4F9F72D4DC1B8F7870BC0C379ADEEE5A405C2AB1FE4308851FBB303F'
    $cache = Join-Path $RepoRoot '.neuraldoom-cache'
    foreach ($candidate in @((Join-Path $RepoRoot 'base/_rbdoom_global_illumination_data.pk4'), (Join-Path $cache 'lighting/base/_rbdoom_global_illumination_data.pk4'))) {
        if ((Test-Path -LiteralPath $candidate) -and (Get-FileHash -LiteralPath $candidate).Hash -eq $packHash) {
            Write-Host 'Using the already verified RBDOOM lighting pack.'
            return $candidate
        }
    }
    Write-Host 'Preparing RBDOOM lighting data: approximately 1.65 GB download from the official release.'
    Write-SetupStatus 'Downloading lighting data...'
    $archive = Get-SetupDownload -Uri 'https://github.com/RobertBeckebans/RBDOOM-3-BFG/releases/download/v1.6.0/RBDOOM-3-BFG-1.6.0.22-full-win64-20250510-git-ba39ba6.7z' -Destination (Join-Path $cache 'rbdoom-1.6.0.7z') -Bytes 1647091125 -Sha256 'F1B9A325CEDE2A281ECE7D10A1A8BC48CE760D12AE23E37C62308631A886ABAE'
    $extractor = Get-SetupDownload -Uri 'https://github.com/ip7z/7zip/releases/download/26.03/7zr.exe' -Destination (Join-Path $cache '7zr-26.03.exe') -Bytes 602624 -Sha256 'AD4C82FADCBDF93C03B4FC440F300509C7D60C5C2F4D183E35D9D70D6957037D'
    $destination = Join-Path $cache 'lighting'
    Write-Host 'Extracting and verifying the lighting pack...'
    Write-SetupStatus 'Extracting and verifying lighting data...'
    # Extract exactly one known member, never the upstream EXE/shaders or full archive.
    & $extractor x -y "-o$destination" $archive 'base/_rbdoom_global_illumination_data.pk4' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Lighting extraction failed. Rerun setup to retry the cached archive.' }
    $pack = Join-Path $destination 'base/_rbdoom_global_illumination_data.pk4'
    if (-not (Test-Path -LiteralPath $pack) -or (Get-Item -LiteralPath $pack).Length -ne 1478656988 -or
        (Get-FileHash -LiteralPath $pack).Hash -ne $packHash) { throw 'Extracted lighting pack failed verification.' }
    return $pack
}

function Test-SetupVCRuntime {
    # Match or exceed the MSVC 14.43 toolset used for the shipped native Release.
    foreach ($dll in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
        $path = Join-Path $env:WINDIR "System32/$dll"
        if (-not (Test-Path -LiteralPath $path)) { return $false }
        $info = (Get-Item -LiteralPath $path).VersionInfo
        $version = [version]::new($info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart)
        if ($version -lt [version]'14.43.0.0') { return $false }
    }
    return $true
}

function Install-SetupVCRuntime {
    param([string]$RepoRoot)
    if (Test-SetupVCRuntime) { Write-Host 'Microsoft VC++ runtime is already installed.'; return }
    $installer = Get-SetupDownload -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -Destination (Join-Path $RepoRoot '.neuraldoom-cache/vc_redist.x64.exe')
    $signature = Get-AuthenticodeSignature -LiteralPath $installer
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw 'Microsoft runtime installer signature could not be verified; it was not executed.'
    }
    Write-Host 'Installing Microsoft VC++ runtime. Accept the Windows administrator prompt if it appears.'
    Write-SetupStatus 'Installing Microsoft prerequisites. Check for a Windows permission prompt.'
    $process = Start-Process -FilePath $installer -ArgumentList '/install', '/passive', '/norestart' -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -notin @(0, 1638, 3010)) { throw "Microsoft runtime installer failed: $($process.ExitCode). Rerun setup after resolving the Windows prompt." }
    if ($process.ExitCode -eq 3010) { Write-Host 'Windows requests a restart before playing. Setup will finish without restarting your PC.' }
    elseif (-not (Test-SetupVCRuntime)) { throw 'Microsoft runtime is still missing or too old. Resolve its installer error and rerun setup.' }
}

function Find-SetupBFG {
    $candidates = @()
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 208200', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 208200')) {
        $entry = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($entry -and $entry.PSObject.Properties['InstallLocation']) { $candidates += $entry.InstallLocation }
    }
    $steam = Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if ($steam -and $steam.PSObject.Properties['SteamPath']) {
        $libraries = @($steam.SteamPath)
        $vdf = Join-Path $steam.SteamPath 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($match in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) { $libraries += $match.Groups[1].Value.Replace('\\', '\') }
        }
        foreach ($library in $libraries) { $candidates += Join-Path $library 'steamapps/common/DOOM 3 BFG Edition' }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'base/maps/mars_city2.resources'))) { return $candidate }
    }
    return $null
}
