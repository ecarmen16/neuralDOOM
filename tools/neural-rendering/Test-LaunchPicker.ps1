[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'LaunchPicker.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
foreach ($availability in @(@($true,$true,'NR'), @($true,$false,'DLAA'), @($false,$false,'Native'))) {
    $picker = New-Object NeuralDoom.LaunchPicker($availability[0], $availability[1], '', 1)
    try {
        if ($picker.SelectedProfile -ne $availability[2]) { throw 'Incorrect default for available components.' }
        $profiles = $picker.GetType().GetField('profiles',$flags).GetValue($picker)
        $quality = $picker.GetType().GetField('reconstruction',$flags).GetValue($picker)
        $details = $picker.GetType().GetField('details',$flags).GetValue($picker)
        for ($p = 0; $p -lt $profiles.Items.Count; $p++) {
            $profiles.SelectedIndex = $p
            for ($mode = 0; $mode -le 4; $mode++) {
                $quality.SelectedIndex = $mode
                if ($picker.SelectedReconstruction -ne $mode) { throw 'Quality mapping changed.' }
                if ($quality.Enabled -ne ($picker.SelectedProfile -eq 'DLAA')) { throw 'NR or Native allows incompatible reconstruction.' }
                $size = [Windows.Forms.TextRenderer]::MeasureText($details.Text, $details.Font, $details.Size, [Windows.Forms.TextFormatFlags]::WordBreak)
                if ($size.Height -gt $details.Height) { throw 'Mode explanation is clipped.' }
            }
        }
        if ($picker.AcceptButton.DialogResult -ne 'OK' -or $picker.CancelButton.DialogResult -ne 'Cancel') { throw 'Play/cancel mapping changed.' }
    } finally { $picker.Dispose() }
}
foreach ($profile in @('NR','DLAA','Native')) {
    $picker = New-Object NeuralDoom.LaunchPicker($true, $true, $profile, 3)
    try {
        if ($picker.SelectedProfile -ne $profile -or $picker.SelectedReconstruction -ne 3) { throw 'Saved selection was lost.' }
    } finally { $picker.Dispose() }
}
Write-Host 'PASS: launcher availability/defaults, saved selection, all quality mappings, NR isolation, text fit and Play/Cancel. No game launched.'
