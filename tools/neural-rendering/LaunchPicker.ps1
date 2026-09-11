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
    [Windows.Forms.Application]::EnableVisualStyles()
    if (-not ('NeuralDoom.LaunchPicker' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'LaunchPicker.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
    }
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $RepoRoot 'captures/dogfood/base/neural_settings_reset.pending')) {
            $PreferredProfile = ''; $PreferredMode = 1; $PreferredNRMode = 1
        }
        $picker = New-Object NeuralDoom.LaunchPicker($sdkAvailable, $nrAvailable, $PreferredProfile, $PreferredMode, $PreferredNRMode)
        $picker.add_SnapshotRequested({
            $dialog = New-Object Windows.Forms.SaveFileDialog
            try {
                . (Join-Path $PSScriptRoot 'Save-NeuralSettingsSnapshot.ps1')
                $directory = Get-NeuralSettingsResetPath $RepoRoot 'settings-snapshots'
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
                $dialog.Title = 'Save personal settings snapshot'
                $dialog.Filter = 'Settings snapshot (*.zip)|*.zip'
                $dialog.DefaultExt = 'zip'; $dialog.AddExtension = $true
                $dialog.InitialDirectory = $directory
                $dialog.FileName = 'neuralDoom-settings-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip'
                if ($dialog.ShowDialog($picker) -ne [Windows.Forms.DialogResult]::OK) { return }
                $saved = Save-NeuralSettingsSnapshot -RepoRoot $RepoRoot -Destination $dialog.FileName
                $notes = if ($saved.Warnings.Count) { "`n`n" + ($saved.Warnings -join "`n") } else { '' }
                $null = [Windows.Forms.MessageBox]::Show($picker,
                    "Settings snapshot saved:`n$($saved.Path)`n`nYour settings are unchanged. This personal ZIP may contain local paths; it is not a preset to ship publicly.$notes",
                    'Snapshot saved', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)
            } catch {
                $null = [Windows.Forms.MessageBox]::Show($picker, $_.Exception.Message, 'Could not save snapshot',
                    [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning)
            } finally { $dialog.Dispose() }
        })
        try {
            $result = $picker.ShowDialog()
            if ($result -eq [Windows.Forms.DialogResult]::Retry) {
                try {
                    . (Join-Path $PSScriptRoot 'Reset-NeuralSettings.ps1')
                    $backup = Reset-NeuralGameSettings -RepoRoot $RepoRoot
                    $null = [Windows.Forms.MessageBox]::Show($picker,
                        "Defaults are ready. Game preferences will finish resetting on the next launch.`n`nSaved games and progress are preserved.`n`nSettings backup:`n$backup",
                        'Defaults restored', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)
                } catch {
                    $null = [Windows.Forms.MessageBox]::Show($picker, $_.Exception.Message, 'Could not restore defaults',
                        [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning)
                }
                continue
            }
            if ($result -ne [Windows.Forms.DialogResult]::OK) { return $null }
            return [pscustomobject]@{ Profile = $picker.SelectedProfile; Mode = $picker.SelectedReconstruction }
        } finally { $picker.Dispose() }
    }
}
