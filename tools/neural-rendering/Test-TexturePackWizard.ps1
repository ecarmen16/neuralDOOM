$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'InternalSetup.cs') -Raw
$source = $source.Replace('class SetupWindow : Form {', 'class SetupWindow : Form { protected override bool ShowWithoutActivation { get { return true; } }')
$types = Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Core -PassThru
$type = $types | Where-Object Name -EQ 'SetupWindow'
$flags = [Reflection.BindingFlags]'Public,NonPublic,Instance'
$window = [Activator]::CreateInstance($type)
try {
    $null = $type.GetMethod('ShowPage',$flags).Invoke($window,@(8))
    $check = $type.GetField('texturePack',$flags).GetValue($window)
    $path = $type.GetField('textureFile',$flags).GetValue($window)
    if (-not $check.Checked -or -not $path.Enabled) { throw 'Texture pack is not initially selectable.' }
    $check.Checked = $false
    if ($path.Enabled) { throw 'Disabled pack left its path active.' }
    if (-not $type.GetMethod('ReadTextures',$flags).Invoke($window,@())) { throw 'Skip selection failed.' }
    $null = $type.GetMethod('ShowPage',$flags).Invoke($window,@(2))
    $back = $type.GetField('back',$flags).GetValue($window)
    $null = [Windows.Forms.Button].GetMethod('OnClick',$flags).Invoke($back,@([EventArgs]::Empty))
    if ($type.GetField('page',$flags).GetValue($window) -ne 8) { throw 'Review Back skipped texture selection.' }
    if ($type.GetField('texturePack',$flags).GetValue($window).Checked) { throw 'Back lost the skip choice.' }
    $check = $type.GetField('texturePack',$flags).GetValue($window)
    $check.Checked = $true
    $window.Opacity = 0
    $window.ShowInTaskbar = $false
    $window.Show()
    [Windows.Forms.Application]::DoEvents()
    $bitmap = New-Object Drawing.Bitmap $window.Width,$window.Height
    try {
        $window.DrawToBitmap($bitmap, $window.ClientRectangle)
        $image = Join-Path $PSScriptRoot '../../captures/neural/texture-wizard.png'
        $bitmap.Save($image)
    } finally { $bitmap.Dispose() }
} finally { $window.Dispose() }
Write-Host 'PASS: texture opt-in, disabled field, review Back navigation and choice persistence. Rendered hidden form; no installer or game launched.'
