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
            $first = if ($picker.SelectedProfile -eq 'NR') { 1 } else { 0 }
            if ($quality.Enabled -ne ($picker.SelectedProfile -ne 'Native')) { throw 'Reconstruction availability changed.' }
            $count = if ($picker.SelectedProfile -eq 'Native') { 0 } else { 5 - $first }
            if ($quality.Items.Count -ne $count) { throw 'Profile offers an invalid reconstruction option.' }
            for ($mode = $first; $mode -le 4 -and $count -gt 0; $mode++) {
                $quality.SelectedIndex = $mode - $first
                if ($picker.SelectedReconstruction -ne $mode) { throw 'Quality mapping changed.' }
                $size = [Windows.Forms.TextRenderer]::MeasureText($details.Text, $details.Font, $details.Size, [Windows.Forms.TextFormatFlags]::WordBreak)
                if ($size.Height -gt $details.Height) { throw 'Mode explanation is clipped.' }
            }
            $size = [Windows.Forms.TextRenderer]::MeasureText($details.Text, $details.Font, $details.Size, [Windows.Forms.TextFormatFlags]::WordBreak)
            if ($size.Height -gt $details.Height) { throw 'Profile explanation is clipped.' }
        }
        if ($picker.AcceptButton.DialogResult -ne 'OK' -or $picker.CancelButton.DialogResult -ne 'Cancel') { throw 'Play/cancel mapping changed.' }
    } finally { $picker.Dispose() }
}
foreach ($profile in @('NR','DLAA','Native')) {
    $picker = New-Object NeuralDoom.LaunchPicker($true, $true, $profile, 3, 2)
    try {
        $expected = if ($profile -eq 'NR') { 2 } elseif ($profile -eq 'DLAA') { 3 } else { 0 }
        if ($picker.SelectedProfile -ne $profile -or $picker.SelectedReconstruction -ne $expected) { throw 'Saved selection was lost.' }
    } finally { $picker.Dispose() }
}
$picker = New-Object NeuralDoom.LaunchPicker($true, $true, 'NR', 4)
try {
    if ($picker.SelectedReconstruction -ne 1) { throw 'New NR profile inherited an SDK preset.' }
    $profiles = $picker.GetType().GetField('profiles',$flags).GetValue($picker)
    $quality = $picker.GetType().GetField('reconstruction',$flags).GetValue($picker)
    $quality.SelectedIndex = 1 # NR Quality
    $profiles.SelectedIndex = 1 # SDK-only Performance
    if ($picker.SelectedReconstruction -ne 4) { throw 'NR changed the saved SDK choice.' }
    $quality.SelectedIndex = 0 # SDK TAA
    $profiles.SelectedIndex = 2 # Native
    if ($picker.SelectedReconstruction -ne 0) { throw 'Native inherited a neural preset.' }
    $profiles.SelectedIndex = 0
    if ($picker.SelectedReconstruction -ne 2) { throw 'NR Quality was lost after switching profiles.' }
    $profiles.SelectedIndex = 1
    if ($picker.SelectedReconstruction -ne 0) { throw 'SDK TAA was lost after switching profiles.' }
} finally { $picker.Dispose() }
Write-Host 'PASS: launcher availability/defaults, independent saved choices, all quality mappings, text fit and Play/Cancel. No game launched.'
