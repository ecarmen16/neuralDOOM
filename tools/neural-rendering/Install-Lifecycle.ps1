# Per-install ownership and reversible upgrades. Never recursively delete an install.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SetupSafePath {
    param([string]$Root, [string]$Relative)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (-not $Relative -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[/\\])\.\.([/\\]|$)|:') { throw 'Unsafe installation path.' }
    $path = [IO.Path]::GetFullPath((Join-Path $rootPath $Relative))
    if (-not $path.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe installation path.' }
    $parent = $path
    while ($parent) {
        if ((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Setup cannot modify a linked installation path.' }
        $parent = Split-Path -Parent $parent
    }
    return $path
}

function Get-SetupFiles {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return }
    $null = Get-SetupSafePath $Root '.neuraldoom-install.json'
    $queue = New-Object 'Collections.Generic.Queue[string]'
    $queue.Enqueue([IO.Path]::GetFullPath($Root).TrimEnd('\'))
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    while ($queue.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Setup cannot traverse linked installation content.' }
            $relative = $item.FullName.Substring($prefix.Length).Replace('\', '/')
            if ($relative -match '^(captures|\.neuraldoom-cache)(/|$)') { continue }
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
            else { $relative }
        }
    }
}

function Assert-SetupInstallRoot {
    param([string]$Root, [switch]$Existing)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if ($rootPath -eq [IO.Path]::GetPathRoot($rootPath).TrimEnd('\') -or
        (Test-Path -LiteralPath (Join-Path $rootPath '.git'))) { throw 'Choose an installation directory, not a drive or source checkout.' }
    $null = Get-SetupSafePath $rootPath 'internal-package.json'
    if ($Existing) {
        $marker = Get-Content -LiteralPath (Join-Path $rootPath 'internal-package.json') -Raw | ConvertFrom-Json
        if ($marker.schemaVersion -ne 2 -or $marker.commit -notmatch '^[0-9a-f]{40}$' -or $marker.executable -ne 'build-rt/Release/neuralDoom.exe') { throw 'This folder is not a recognized neuralDoom installation.' }
    }
    foreach ($process in Get-Process -Name neuralDoom, RBDoom3BFG -ErrorAction SilentlyContinue) {
        if (-not $process.Path -or $process.Path.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Close the running neuralDoom game before changing this installation.' }
    }
}

function Get-SetupInstallId {
    param([string]$Root)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Root).TrimEnd('\').ToLowerInvariant()))).Replace('-', '').Substring(0, 16)) }
    finally { $sha.Dispose() }
}

function Register-SetupInstallation {
    param([string]$Root, [string]$Profile, [string]$GamePath, [string[]]$Before, $OldState, [string[]]$UpdatedPaths = @(), [switch]$SkipRegistration)
    $package = Get-Content -LiteralPath (Join-Path $Root 'internal-package.json') -Raw | ConvertFrom-Json
    $owned = @{}; $oldPaths = @{}; $expected = @{}
    foreach ($path in $Before) { $oldPaths[$path] = $true }
    if ($OldState) { foreach ($file in $OldState.files) { $owned[$file.path] = $true; $expected[$file.path] = $file.sha256 } }
    foreach ($path in $UpdatedPaths) { $expected.Remove($path) }
    foreach ($file in $package.files) { $owned[$file.path] = $true; $expected[$file.path] = $file.sha256 }
    foreach ($path in Get-SetupFiles $Root) { if (-not $oldPaths.ContainsKey($path)) { $owned[$path] = $true } }
    # Saves, runtime tuning, and installer caches are always user-owned.
    $records = @(foreach ($path in $owned.Keys | Sort-Object) {
        if ($path -match '^(captures|\.neuraldoom-cache)(/|$)|(^|/)(D3BFGConfig\.cfg|autoexec\.cfg|reshade\.ini|imgui\.ini)$|^\.neuraldoom-install\.json$') { continue }
        $full = Get-SetupSafePath $Root $path
        if (Test-Path -LiteralPath $full -PathType Leaf) { @{ path = $path; sha256 = $(if ($expected.ContainsKey($path)) { $expected[$path] } else { (Get-FileHash -LiteralPath $full).Hash }) } }
    })
    $id = Get-SetupInstallId $Root
    $state = @{ schemaVersion = 1; id = $id; commit = $package.commit; profile = $Profile; gamePath = $GamePath; files = $records }
    $state | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $Root '.neuraldoom-install.json') -Encoding UTF8
    if ($SkipRegistration) { return }
    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\neuralDoom-$id"
    $null = New-Item -Path $key -Force
    $command = '"' + (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') + '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Root 'tools/neural-rendering/Uninstall-InternalTest.ps1') + '" -RepoRoot "' + $Root.TrimEnd('\') + '"'
    foreach ($entry in @{
        DisplayName = "neuralDoom Internal ($id)"; DisplayVersion = $package.commit.Substring(0,8)
        InstallLocation = $Root; DisplayIcon = (Join-Path $Root $package.executable); UninstallString = $command
        Publisher = 'neuralDoom contributors'
    }.GetEnumerator()) { $null = New-ItemProperty -Path $key -Name $entry.Key -Value $entry.Value -PropertyType String -Force }
    foreach ($name in @('NoModify', 'NoRepair')) { $null = New-ItemProperty -Path $key -Name $name -Value 1 -PropertyType DWord -Force }
}

function Remove-SetupInstallation {
    param([string]$Root, [switch]$SkipRegistration)
    Assert-SetupInstallRoot $Root -Existing
    $statePath = Get-SetupSafePath $Root '.neuraldoom-install.json'
    $package = Get-Content -LiteralPath (Join-Path $Root 'internal-package.json') -Raw | ConvertFrom-Json
    $state = if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } else { $null }
    # Legacy installs have no full ownership inventory: remove verified package
    # files only and keep copied data. Never infer ownership from a file extension.
    $records = if ($state) { @($state.files) } else { @($package.files) }
    $null = @(Get-SetupFiles $Root) # Reject linked trees before deleting any file.
    $validated = @(foreach ($file in $records) { @{ path = (Get-SetupSafePath $Root $file.path); relative = $file.path; hash = $file.sha256 } })
    $kept = 0
    foreach ($file in $validated) {
        if ($file.relative -match '^(captures|\.neuraldoom-cache)(/|$)|(^|/)(D3BFGConfig\.cfg|autoexec\.cfg|reshade\.ini|imgui\.ini)$') { continue }
        if (Test-Path -LiteralPath $file.path -PathType Leaf) {
            if ((Get-FileHash -LiteralPath $file.path).Hash -eq $file.hash) { Remove-Item -LiteralPath $file.path -Force }
            else { $kept++ }
        }
    }
    # These two installer-owned records are validated above; they are not user data.
    foreach ($name in @('.neuraldoom-install.json', 'internal-package.json')) {
        $path = Get-SetupSafePath $Root $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if (-not $SkipRegistration) {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\neuralDoom-' + (Get-SetupInstallId $Root)
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key }
        $shell = New-Object -ComObject WScript.Shell
        foreach ($folder in @([Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('Programs')) 'neuralDoom'))) {
            if (-not (Test-Path -LiteralPath $folder)) { continue }
            foreach ($link in Get-ChildItem -LiteralPath $folder -Filter 'neuralDoom*.lnk' -File) {
                if ($shell.CreateShortcut($link.FullName).TargetPath -ieq (Join-Path $Root 'Play-InternalTest.cmd')) { Remove-Item -LiteralPath $link.FullName }
            }
        }
    }
    Write-Host "Removed verified application files. Saves, settings, cached downloads and $kept modified files remain in $Root."
}

function Invoke-SetupDeployment {
    param([string]$Stage, [string]$Destination, [ValidateSet('New','Upgrade','Copy')][string]$Mode,
        [string]$ExistingPath, [string]$GamePath, [string]$Profile, [string]$DlssDllPath, [string]$NRDllPath,
        [switch]$IncludeD3HDP, [string]$D3HDPArchivePath,
        [switch]$SkipShortcut, [switch]$SkipStartMenu, [switch]$SkipRegistration)
    Assert-SetupInstallRoot $Destination -Existing:($Mode -eq 'Upgrade')
    if ($Mode -ne 'Upgrade' -and (Test-Path -LiteralPath $Destination) -and @(Get-SetupFiles $Destination).Count) { throw 'A separate installation needs an empty folder. Choose Upgrade to replace a recognized installation.' }
    if ($Mode -eq 'Copy') {
        Assert-SetupInstallRoot $ExistingPath -Existing
        $from = [IO.Path]::GetFullPath($ExistingPath).TrimEnd('\'); $to = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
        if ($to -ieq $from -or $to.StartsWith($from + '\', [StringComparison]::OrdinalIgnoreCase) -or $from.StartsWith($to + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'The copy destination must be outside the existing installation.' }
        $GamePath = $ExistingPath
    }
    if ($GamePath) {
        $gameRoot = [IO.Path]::GetFullPath($GamePath).TrimEnd('\'); $targetRoot = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
        if (-not ($Mode -eq 'Upgrade' -and $gameRoot -ieq $targetRoot) -and ($gameRoot -ieq $targetRoot -or $targetRoot.StartsWith($gameRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or $gameRoot.StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase))) { throw 'The owned game and installation directories must be separate.' }
    }
    $before = @(Get-SetupFiles $Destination)
    $oldState = $null
    if (Test-Path -LiteralPath (Join-Path $Destination '.neuraldoom-install.json')) { $oldState = Get-Content -LiteralPath (Join-Path $Destination '.neuraldoom-install.json') -Raw | ConvertFrom-Json }
    $payload = Get-Content -LiteralPath (Join-Path $Stage 'internal-package.json') -Raw | ConvertFrom-Json
    $replace = @($payload.files.path) + @('internal-package.json', '.neuraldoom-install.json', 'reshade.ini', 'neuralDoom.exe',
        'build-rt/neuraldoom-build-Release.json', 'build-rt/neuraldoom-artifact-Release.txt',
        'build-streamline/neuraldoom-build-Release.json', 'build-streamline/neuraldoom-artifact-Release.txt')
    foreach ($name in @('sl.interposer.dll','sl.common.dll','sl.dlss.dll','nvngx_dlss.dll','nvngx_dlssnr.dll','neuraldoom-reshade64.dll','renodx-dlss5.addon64')) {
        $replace += $name; $replace += "build-streamline/Release/$name"
    }
    $replace += @($before | Where-Object { $_ -like 'third-party-notices/*' })
    $backup = Join-Path $Destination ('.neuraldoom-cache/rollback/' + [guid]::NewGuid().ToString('N'))
    $null = Get-SetupSafePath $Destination '.neuraldoom-cache/rollback'
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $saved = @()
    foreach ($relative in $replace | Select-Object -Unique) {
        $path = Get-SetupSafePath $Destination $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $copy = Get-SetupSafePath $backup $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null
            Copy-Item -LiteralPath $path -Destination $copy
            $saved += $relative
        }
    }
    @{ before = $before; saved = $saved; status = 'pending' } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backup 'transaction.json')
    try {
        Write-Host '@@SETUP|Installing verified application files...'
        foreach ($relative in @($payload.files.path) + 'internal-package.json') {
            $source = Get-SetupSafePath $Stage $relative; $target = Get-SetupSafePath $Destination $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
        if ($Mode -eq 'Copy') {
            $saveSource = Get-SetupSafePath $ExistingPath 'captures/dogfood'
            $saveTarget = Get-SetupSafePath $Destination 'captures/dogfood'
            if (Test-Path -LiteralPath $saveSource) {
                # Inspect save links as well; robocopy is not allowed to follow them.
                $null = @(Get-SetupFiles $saveSource)
                & robocopy $saveSource $saveTarget /E /XJ /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Host
                if ($LASTEXITCODE -gt 7) { throw 'Could not copy existing saves.' }
            }
            $sourceIni = Get-SetupSafePath $ExistingPath 'reshade.ini'
            if (Test-Path -LiteralPath $sourceIni) { Copy-Item -LiteralPath $sourceIni -Destination (Join-Path $Destination 'reshade.ini') }
        }
        & (Join-Path $Destination 'tools/neural-rendering/Install-InternalTest.ps1') -RepoRoot $Destination -GamePath $GamePath -Profile $Profile -DlssDllPath $DlssDllPath -NRDllPath $NRDllPath -IncludeD3HDP:$IncludeD3HDP -D3HDPArchivePath $D3HDPArchivePath -SkipShortcut:$SkipShortcut -SkipStartMenu:$SkipStartMenu -NonInteractive -ManagedDeployment
        # Remove obsolete package files only when unchanged; modified files remain.
        if ($Mode -eq 'Upgrade') {
            $oldPackage = Get-Content -LiteralPath (Join-Path $backup 'internal-package.json') -Raw | ConvertFrom-Json
            $current = @{}; foreach ($file in $payload.files) { $current[$file.path] = $true }
            foreach ($file in $oldPackage.files) {
                $path = Get-SetupSafePath $Destination $file.path
                if (-not $current.ContainsKey($file.path) -and (Test-Path -LiteralPath $path -PathType Leaf) -and (Get-FileHash -LiteralPath $path).Hash -eq $file.sha256) {
                    $copy = Get-SetupSafePath $backup $file.path
                    New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null
                    Copy-Item -LiteralPath $path -Destination $copy -Force; $saved += $file.path
                    Remove-Item -LiteralPath $path -Force
                }
            }
        }
        $updated = @(foreach ($path in $saved) {
            $currentPath = Get-SetupSafePath $Destination $path
            if ((Test-Path -LiteralPath $currentPath -PathType Leaf) -and (Get-FileHash -LiteralPath $currentPath).Hash -ne (Get-FileHash -LiteralPath (Get-SetupSafePath $backup $path)).Hash) { $path }
        })
        Register-SetupInstallation -Root $Destination -Profile $Profile -GamePath $GamePath -Before $before -OldState $oldState -UpdatedPaths $updated -SkipRegistration:$SkipRegistration
        # Apply the setup selection once even when an older saved menu chose Native.
        $pending = Get-SetupSafePath $Destination 'captures/dogfood/installed-profile.pending'
        New-Item -ItemType Directory -Path (Split-Path -Parent $pending) -Force | Out-Null
        $Profile | Set-Content -LiteralPath $pending -Encoding ASCII
        'complete' | Set-Content -LiteralPath (Join-Path $backup 'status.txt')
    } catch {
        $failure = $_
        Write-Host '@@SETUP|Restoring the previous application files...'
        $prior = @{}; foreach ($path in $before) { $prior[$path] = $true }
        foreach ($relative in Get-SetupFiles $Destination) {
            if (-not $prior.ContainsKey($relative)) { Remove-Item -LiteralPath (Get-SetupSafePath $Destination $relative) -Force }
        }
        foreach ($relative in $saved) { Copy-Item -LiteralPath (Get-SetupSafePath $backup $relative) -Destination (Get-SetupSafePath $Destination $relative) -Force }
        'restored after failure' | Set-Content -LiteralPath (Join-Path $backup 'status.txt')
        throw $failure
    }
}
