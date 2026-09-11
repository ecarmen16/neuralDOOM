# Exercise the real constructor/navigation with only installation discovery replaced.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('neuraldoom-upgrade-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
'{}' | Set-Content -LiteralPath (Join-Path $fixture 'internal-package.json')
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'InternalSetup.cs') -Raw
$source = $source.Replace('gamePath = FindBFG(); FindInstallations();', 'gamePath = ""; AddInstallation(@"' + $fixture.Replace('"','""') + '");')
$types = Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Core -PassThru
$type = $types | Where-Object Name -EQ 'SetupWindow'
$flags = [Reflection.BindingFlags]'Public,NonPublic,Instance'
$window = [Activator]::CreateInstance($type)
try {
    if ($window.Visible) { throw 'Hidden constructor test displayed a window.' }
    if ($type.GetField('installPath',$flags).GetValue($window) -ne $fixture) { throw 'Default upgrade retained the new-install destination.' }
    $null = $type.GetMethod('ShowPage',$flags).Invoke($window,@(7))
    if (-not $type.GetMethod('ReadManagement',$flags).Invoke($window,@())) { throw 'Default upgrade selection was rejected.' }
    $null = $type.GetMethod('ShowPage',$flags).Invoke($window,@(1))
    $destination = $type.GetField('destination',$flags).GetValue($window)
    if ($destination.Text -ne $fixture -or -not $destination.ReadOnly) { throw 'Upgrade destination does not match the selected installation.' }
} finally { $window.Dispose() }
Write-Host 'PASS: default detected upgrade keeps the selected destination through unchanged navigation. No windows shown or installer run.'
