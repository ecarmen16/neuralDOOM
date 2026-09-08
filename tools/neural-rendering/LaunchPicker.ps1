function Show-NeuralLaunchPicker {
    param([string]$RepoRoot, [string]$BuildDirectory, [string]$Configuration,
        [string]$PreferredProfile, [int]$PreferredMode = 1, [int]$PreferredNRMode = 1)

    $sdkBuild = if ($BuildDirectory) { $BuildDirectory } else { Join-Path $RepoRoot 'build-streamline' }
    $sdkExe = $null
    if (Test-Path -LiteralPath (Join-Path $sdkBuild "neuraldoom-artifact-$Configuration.txt")) {
        $sdkExe = Find-NeuralDoomExecutable -RepoRoot $RepoRoot -BuildDirectory $sdkBuild -Configuration $Configuration
    }
    $sdkAvailable = $false
    $manifestPath = Join-Path $sdkBuild "neuraldoom-build-$Configuration.json"
    if ($sdkExe -and (Test-Path -LiteralPath $manifestPath)) {
        $sdkManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $sdkAvailable = $sdkManifest.features.streamline -eq 'ON'
        foreach ($dll in @('sl.interposer.dll', 'sl.common.dll', 'sl.dlss.dll', 'nvngx_dlss.dll')) {
            $sdkAvailable = $sdkAvailable -and (Test-Path -LiteralPath (Join-Path (Split-Path $sdkExe) $dll) -PathType Leaf)
        }
    }
    $nrAvailable = $sdkAvailable
    foreach ($dll in @('neuraldoom-reshade64.dll', 'renodx-dlss5.addon64', 'nvngx_dlssnr.dll')) {
        $nrAvailable = $nrAvailable -and (Test-Path -LiteralPath (Join-Path $RepoRoot $dll) -PathType Leaf)
    }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    if (-not ('NeuralDoom.LaunchPicker' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'LaunchPicker.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
    }
    $picker = New-Object NeuralDoom.LaunchPicker($sdkAvailable, $nrAvailable, $PreferredProfile, $PreferredMode, $PreferredNRMode)
    try {
        if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
        return [pscustomobject]@{ Profile = $picker.SelectedProfile; Mode = $picker.SelectedReconstruction }
    } finally { $picker.Dispose() }
}
