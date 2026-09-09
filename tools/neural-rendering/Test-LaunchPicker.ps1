[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# Replace only the modal confirmation boundary in memory. The real Click handler
# runs against both answers without showing a window or invoking a reset helper.
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'LaunchPicker.cs') -Raw
if ([regex]::Matches($source, 'MessageBox\.Show\(').Count -ne 1) { throw 'Review the changed confirmation boundary.' }
$source = $source.Replace('MessageBox.Show(', 'LaunchPickerTestConfirmation.Show(')
$stub = @'
namespace NeuralDoom {
    public static class LaunchPickerTestConfirmation {
        public static System.Windows.Forms.DialogResult NextResult = System.Windows.Forms.DialogResult.Cancel;
        public static int Calls;
        public static string Message;
        public static System.Windows.Forms.MessageBoxButtons Buttons;
        public static System.Windows.Forms.MessageBoxDefaultButton DefaultButton;
        public static System.Windows.Forms.DialogResult Show(System.Windows.Forms.IWin32Window owner,
            string message, string caption, System.Windows.Forms.MessageBoxButtons buttons,
            System.Windows.Forms.MessageBoxIcon icon, System.Windows.Forms.MessageBoxDefaultButton defaultButton) {
            Calls++; Message = message; Buttons = buttons; DefaultButton = defaultButton; return NextResult;
        }
    }
}
'@
Add-Type -TypeDefinition ($source + $stub) -ReferencedAssemblies System.Windows.Forms, System.Drawing
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
$profileIds = @('Native', 'DLAA', 'NR')
$modeNames = @('Native TAA', 'DLAA', 'Quality', 'Balanced', 'Performance')
$script:cases = 0

function Get-PickerField($Picker, [string]$Name) {
    $Picker.GetType().GetField($Name, $flags).GetValue($Picker)
}
function Assert-TextFits([string]$Text, $Font, [Drawing.Size]$Bounds, [bool]$Wrap, [string]$Context) {
    $textFlags = [Windows.Forms.TextFormatFlags]::NoPrefix
    if ($Wrap) { $textFlags = $textFlags -bor [Windows.Forms.TextFormatFlags]::WordBreak }
    $size = [Windows.Forms.TextRenderer]::MeasureText($Text, $Font, $Bounds, $textFlags)
    if ($size.Height -gt $Bounds.Height -or $size.Width -gt $Bounds.Width) { throw "Text clipped in ${Context}: '$Text' needs $size, has $Bounds." }
}
function Assert-PickerState($Picker, [string]$Profile, [int]$Mode, [bool]$SDK, [bool]$NR) {
    if ($Picker.Visible) { throw 'A test made the picker visible.' }
    if ($Picker.SelectedProfile -ne $Profile -or $Picker.SelectedReconstruction -ne $Mode) { throw "Expected $Profile/$Mode; got $($Picker.SelectedProfile)/$($Picker.SelectedReconstruction)." }
    $profiles = Get-PickerField $Picker 'profiles'
    $quality = Get-PickerField $Picker 'reconstruction'
    if ($profiles.Length -ne 3 -or $quality.Length -ne 5) { throw 'Fixed profile/mode indices changed.' }
    $enabledProfiles = @($true, $SDK, ($SDK -and $NR))
    for ($p = 0; $p -lt 3; $p++) {
        if ($profiles[$p] -isnot [Windows.Forms.RadioButton] -or $profiles[$p].Enabled -ne $enabledProfiles[$p] -or
            $profiles[$p].Checked -ne ($profileIds[$p] -eq $Profile)) { throw "Profile radio state/index $p changed." }
    }
    for ($m = 0; $m -lt 5; $m++) {
        $enabled = $Profile -eq 'DLAA' -or ($Profile -eq 'NR' -and $m -gt 0) -or ($Profile -eq 'Native' -and $m -eq 0)
        if ($quality[$m] -isnot [Windows.Forms.RadioButton] -or $quality[$m].Text -ne $modeNames[$m] -or
            $quality[$m].Enabled -ne $enabled -or $quality[$m].Checked -ne ($m -eq $Mode)) { throw "Reconstruction radio state/index $m changed." }
    }
    foreach ($name in @('details', 'detailTitle', 'status', 'renderScale')) {
        $label = Get-PickerField $Picker $name
        Assert-TextFits $label.Text $label.Font $label.Size ($name -eq 'details') $name
    }
    $scale = Get-PickerField $Picker 'renderScale'
    $bar = Get-PickerField $Picker 'scaleBar'
    $expectedWidth = [int][Math]::Truncate($bar.Parent.ClientSize.Width * @(1, 1, 0.67, 0.58, 0.5)[$Mode])
    if ($scale.Text -ne @('100%', '100%', '~67%', '~58%', '~50%')[$Mode] -or $bar.Width -ne $expectedWidth) { throw 'Render scale disagrees with reconstruction.' }
    $script:cases++
}
function Assert-ChoiceTextFits($Choice) {
    $type = $Choice.GetType()
    $compact = $type.GetField('Compact', $flags).GetValue($Choice)
    $heading = $type.GetField('Heading', $flags).GetValue($Choice)
    $description = $type.GetField('Description', $flags).GetValue($Choice)
    # Custom painter rectangles at 96 DPI, measured without its ellipsis flag.
    $titleSize = if ($compact) { 10 } else { 13 }
    $bodySize = if ($compact) { 9 } else { 9.5 }
    $title = New-Object Drawing.Font('Segoe UI', $titleSize, [Drawing.FontStyle]::Bold)
    $body = New-Object Drawing.Font('Segoe UI', $bodySize)
    $tag = New-Object Drawing.Font('Consolas', 8, [Drawing.FontStyle]::Bold)
    try {
        $y = if ($compact) { 12 } else { 34 }
        Assert-TextFits $heading $title (New-Object Drawing.Size(($Choice.Width - 32), 27)) $false 'choice heading'
        Assert-TextFits $description $body (New-Object Drawing.Size(($Choice.Width - 32), ($Choice.Height - $y - 30))) $true 'choice description'
        if (!$compact) {
            $badge = if ($Choice.Enabled) { $type.GetField('Badge', $flags).GetValue($Choice) } else { 'NOT INSTALLED' }
            Assert-TextFits $badge $tag (New-Object Drawing.Size(($Choice.Width - 32), 16)) $false 'choice badge'
        }
    } finally { $title.Dispose(); $body.Dispose(); $tag.Dispose() }
}

# Include NR present without its SDK prerequisite, unavailable saved profiles,
# unknown profile IDs, every enabled mode, and disabled choices remaining visible.
foreach ($sdk in @($false, $true)) {
    foreach ($nr in @($false, $true)) {
        $fallback = if ($sdk -and $nr) { 'NR' } elseif ($sdk) { 'DLAA' } else { 'Native' }
        foreach ($preferred in @('', 'unknown', 'Native', 'DLAA', 'NR')) {
            $picker = New-Object NeuralDoom.LaunchPicker($sdk, $nr, $preferred, 3, 2)
            try {
                $expected = if ($preferred -eq 'Native' -or ($preferred -eq 'DLAA' -and $sdk) -or ($preferred -eq 'NR' -and $sdk -and $nr)) { $preferred } else { $fallback }
                $expectedMode = if ($expected -eq 'NR') { 2 } elseif ($expected -eq 'DLAA') { 3 } else { 0 }
                Assert-PickerState $picker $expected $expectedMode $sdk $nr
                $profiles = Get-PickerField $picker 'profiles'
                $quality = Get-PickerField $picker 'reconstruction'
                foreach ($choice in @($profiles) + @($quality)) { Assert-ChoiceTextFits $choice }
                for ($p = 0; $p -lt $profiles.Length; $p++) {
                    if (!$profiles[$p].Enabled) { continue }
                    $profiles[$p].Checked = $true
                    for ($mode = 0; $mode -lt $quality.Length; $mode++) {
                        if (!$quality[$mode].Enabled) { continue }
                        $quality[$mode].Checked = $true
                        Assert-PickerState $picker $profileIds[$p] $mode $sdk $nr
                    }
                }
                if ($picker.AcceptButton.Text -ne 'PLAY DOOM 3' -or $picker.AcceptButton.DialogResult -ne 'OK' -or
                    $picker.CancelButton.Text -ne 'Cancel' -or $picker.CancelButton.DialogResult -ne 'Cancel') { throw 'Play/Cancel mapping changed.' }
                foreach ($button in @($picker.AcceptButton, $picker.CancelButton)) { Assert-TextFits $button.Text $button.Font $button.ClientSize $false 'action button' }
                if ($picker.DialogResult -ne 'None' -or [NeuralDoom.LaunchPickerTestConfirmation]::Calls -ne 0) { throw 'Constructing/changing choices initiated an action.' }
            } finally { $picker.Dispose() }
        }
    }
}

foreach ($saved in @(-99, 0, 1, 2, 3, 4, 99)) {
    $picker = New-Object NeuralDoom.LaunchPicker($true, $true, 'DLAA', $saved, $saved)
    try {
        Assert-PickerState $picker 'DLAA' ([Math]::Max(0, [Math]::Min(4, $saved))) $true $true
        (Get-PickerField $picker 'profiles')[2].Checked = $true
        Assert-PickerState $picker 'NR' ([Math]::Max(1, [Math]::Min(4, $saved))) $true $true
    } finally { $picker.Dispose() }
}
$picker = New-Object NeuralDoom.LaunchPicker($true, $true, 'NR', 4)
try {
    Assert-PickerState $picker 'NR' 1 $true $true # New NR must not inherit SDK Performance.
    $profiles = Get-PickerField $picker 'profiles'; $quality = Get-PickerField $picker 'reconstruction'
    $quality[2].Checked = $true; $profiles[1].Checked = $true
    Assert-PickerState $picker 'DLAA' 4 $true $true
    $quality[0].Checked = $true; $profiles[0].Checked = $true
    Assert-PickerState $picker 'Native' 0 $true $true
    $profiles[2].Checked = $true
    Assert-PickerState $picker 'NR' 2 $true $true
    $profiles[1].Checked = $true
    Assert-PickerState $picker 'DLAA' 0 $true $true
} finally { $picker.Dispose() }

$picker = New-Object NeuralDoom.LaunchPicker($true, $true, 'NR', 4, 2)
try {
    $reset = @($picker.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Text -eq 'Restore defaults...' })
    if ($reset.Count -ne 1 -or $reset[0].DialogResult -ne 'None' -or $reset[0] -eq $picker.AcceptButton -or $reset[0] -eq $picker.CancelButton) { throw 'Reset can execute as an implicit dialog action.' }
    Assert-TextFits $reset[0].Text $reset[0].Font $reset[0].ClientSize $false 'reset button'
    $click = [Windows.Forms.Button].GetMethod('OnClick', $flags)
    [NeuralDoom.LaunchPickerTestConfirmation]::NextResult = [Windows.Forms.DialogResult]::Cancel
    $click.Invoke($reset[0], @([EventArgs]::Empty)) | Out-Null
    if ($picker.DialogResult -ne 'None' -or [NeuralDoom.LaunchPickerTestConfirmation]::Calls -ne 1) { throw 'Canceling confirmation requested a reset.' }
    Assert-PickerState $picker 'NR' 2 $true $true
    if ([NeuralDoom.LaunchPickerTestConfirmation]::Buttons -ne 'OKCancel' -or [NeuralDoom.LaunchPickerTestConfirmation]::DefaultButton -ne 'Button2' -or
        [NeuralDoom.LaunchPickerTestConfirmation]::Message -notmatch 'Saved games and progress are preserved' -or
        [NeuralDoom.LaunchPickerTestConfirmation]::Message -notmatch 'backed up' -or
        [NeuralDoom.LaunchPickerTestConfirmation]::Message -notmatch 'Close the game') { throw 'Reset confirmation lost its scope, backup, or cancel-default contract.' }
    [NeuralDoom.LaunchPickerTestConfirmation]::NextResult = [Windows.Forms.DialogResult]::OK
    $click.Invoke($reset[0], @([EventArgs]::Empty)) | Out-Null
    if ($picker.DialogResult -ne 'Retry' -or [NeuralDoom.LaunchPickerTestConfirmation]::Calls -ne 2 -or $picker.Visible) { throw 'Confirmed reset did not return its distinct launcher request.' }
} finally { $picker.Dispose() }
Write-Host "PASS: $script:cases hidden launcher states; fixed radio indices, availability/fallbacks, independent saved modes, clamping, text fit, Play/Cancel and guarded reset request. No windows shown or game launched."
