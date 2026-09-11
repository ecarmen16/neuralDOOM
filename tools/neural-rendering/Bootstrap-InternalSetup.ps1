[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$Sha256,
    [string]$Destination,
    [string]$GamePath,
    [ValidateSet('Native','DLAA','NR')][string]$Profile = 'Native',
    [ValidateSet('New','Upgrade','Copy','Uninstall')][string]$Mode = 'New',
    [string]$ExistingPath,
    [string]$DlssDllPath,
    [string]$NRDllPath,
    [switch]$IncludeD3HDP,
    [string]$D3HDPArchivePath,
    [switch]$SkipRegistration,
    [switch]$SkipShortcut,
    [switch]$SkipStartMenu,
    [switch]$NonInteractive,
    [switch]$ExtractOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($env:NEURALDOOM_SETUP_CANCEL_FILE -and (Test-Path -LiteralPath $env:NEURALDOOM_SETUP_CANCEL_FILE)) { throw 'Setup cancelled.' }
Write-Host '@@SETUP|Verifying setup files...'
if ((Get-FileHash -LiteralPath $PackagePath).Hash -ne $Sha256) { throw 'Setup payload checksum failed. Download setup again.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PackagePath).Path)
try {
    $reader = New-Object IO.StreamReader($archive.GetEntry('internal-package.json').Open())
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if ($manifest.commit -notmatch '^[0-9a-f]{40}$') { throw 'Invalid payload version.' }
    if (-not $Destination) {
        $Destination = Join-Path $env:LOCALAPPDATA ("neuralDoom/Internal/" + $manifest.commit.Substring(0, 8))
        if (-not $NonInteractive -and -not $ExtractOnly) {
            Add-Type -AssemblyName System.Windows.Forms
            $picker = New-Object System.Windows.Forms.FolderBrowserDialog
            try {
                $picker.Description = 'Choose or create an empty folder to install neuralDoom. Your owned BFG game folder is selected separately.'
                $picker.ShowNewFolderButton = $true
                $picker.SelectedPath = $env:LOCALAPPDATA
                if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'Installation cancelled before any files were installed.' }
                $Destination = $picker.SelectedPath
            } finally { $picker.Dispose() }
        }
    }
    $Destination = [IO.Path]::GetFullPath($Destination)
    $prefix = $Destination.TrimEnd('\') + '\'
    $seen = @{}
    foreach ($entry in $archive.Entries) {
        $path = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
        if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $entry.FullName -match ':|(^|[/\\])\.\.([/\\]|$)' -or $seen.ContainsKey($path)) { throw 'Unsafe setup archive path.' }
        $seen[$path] = $true
    }
} finally { $archive.Dispose() }
if ($ExtractOnly) {
    if ((Test-Path -LiteralPath $Destination) -and @(Get-ChildItem -LiteralPath $Destination -Force).Count) { throw 'Extraction requires an empty destination.' }
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $Destination
    return
}
$stage = Join-Path ([IO.Path]::GetTempPath()) ('neuralDoom-payload-' + [guid]::NewGuid().ToString('N'))
try {
    Write-Host '@@SETUP|Extracting verified setup content...'
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $stage
    & (Join-Path $stage 'tools/neural-rendering/Install-InternalTest.ps1') -RepoRoot $stage -VerifyOnly -Profile $Profile
    . (Join-Path $stage 'tools/neural-rendering/Install-Lifecycle.ps1')
    if ($Mode -eq 'Uninstall') { Remove-SetupInstallation -Root $Destination -SkipRegistration:$SkipRegistration; return }
    Invoke-SetupDeployment -Stage $stage -Destination $Destination -Mode $Mode -ExistingPath $ExistingPath -GamePath $GamePath -Profile $Profile -DlssDllPath $DlssDllPath -NRDllPath $NRDllPath -IncludeD3HDP:$IncludeD3HDP -D3HDPArchivePath $D3HDPArchivePath -SkipShortcut:$SkipShortcut -SkipStartMenu:$SkipStartMenu -SkipRegistration:$SkipRegistration
} finally {
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    if ($resolvedStage.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedStage) -like 'neuralDoom-payload-*' -and (Test-Path -LiteralPath $resolvedStage)) { Remove-Item -LiteralPath $resolvedStage -Recurse -Force }
}
