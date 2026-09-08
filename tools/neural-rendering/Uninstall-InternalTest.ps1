[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepoRoot, [switch]$NonInteractive, [switch]$SkipRegistration)
. (Join-Path $PSScriptRoot 'Install-Lifecycle.ps1')
Assert-SetupInstallRoot $RepoRoot -Existing
if (-not $NonInteractive) {
    Add-Type -AssemblyName System.Windows.Forms
    if ([Windows.Forms.MessageBox]::Show("Remove neuralDoom from $RepoRoot ?`n`nSaves, settings, modified files and cached downloads will be kept.", 'Uninstall neuralDoom', 'YesNo', 'Question') -ne 'Yes') { return }
}
try {
    Remove-SetupInstallation $RepoRoot -SkipRegistration:$SkipRegistration
    if (-not $NonInteractive) { [Windows.Forms.MessageBox]::Show('Application files removed. Saves and settings remain in the installation folder.', 'neuralDoom') | Out-Null }
} catch {
    if (-not $NonInteractive) { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Uninstall could not finish', 'OK', 'Error') | Out-Null }
    throw
}
