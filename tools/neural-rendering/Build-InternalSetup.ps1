[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackagePath, [Parameter(Mandatory)][string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw 'Refusing to overwrite an existing setup artifact.' }
$stage = Join-Path (Split-Path -Parent $OutputPath) ('setup-stage-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($PackagePath)
try {
    $reader = New-Object IO.StreamReader($zip.GetEntry('internal-package.json').Open())
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    foreach ($name in @('InternalSetup.cs', 'Bootstrap-InternalSetup.ps1', 'assets/neuraldoom-setup.ico')) {
        $record = @($manifest.files | Where-Object path -EQ "tools/neural-rendering/$name")
        if ($record.Count -ne 1) { throw 'Bootstrap source missing from the package manifest.' }
        $sourceStream = $zip.GetEntry("tools/neural-rendering/$name").Open()
        $stageFile = Join-Path $stage $name
        New-Item -ItemType Directory -Path (Split-Path -Parent $stageFile) -Force | Out-Null
        $targetStream = [IO.File]::Create($stageFile)
        try { $sourceStream.CopyTo($targetStream) } finally { $targetStream.Dispose(); $sourceStream.Dispose() }
        if ((Get-FileHash -LiteralPath $stageFile).Hash -ne $record[0].sha256) { throw 'Packaged bootstrap source hash mismatch.' }
    }
} finally { $zip.Dispose() }
$hashFile = Join-Path $stage 'checksum.txt'
$versionFile = Join-Path $stage 'version.txt'
$neuralFile = Join-Path $stage 'neural.txt'
$(if ($manifest.PSObject.Properties['neuralBuild']) { '1' } else { '0' }) | Set-Content -LiteralPath $neuralFile -Encoding ASCII
$manifest.commit.Substring(0, 8) | Set-Content -LiteralPath $versionFile -Encoding ASCII
(Get-FileHash -LiteralPath $PackagePath).Hash | Set-Content -LiteralPath $hashFile -Encoding ASCII
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows .NET Framework C# compiler is missing.' }
$iconFile = Join-Path $stage 'assets/neuraldoom-setup.ico'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll /reference:System.Drawing.dll ("/win32icon:" + $iconFile) ("/resource:" + $iconFile + ',SetupIcon') ("/out:" + $OutputPath) ("/resource:" + $PackagePath + ',Payload') ("/resource:" + (Join-Path $stage 'Bootstrap-InternalSetup.ps1') + ',Bootstrap') ("/resource:" + $hashFile + ',Checksum') ("/resource:" + $versionFile + ',Version') ("/resource:" + $neuralFile + ',Neural') (Join-Path $stage 'InternalSetup.cs')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputPath)) { throw 'Setup bootstrap compilation failed.' }
$verification = Start-Process -FilePath $OutputPath -ArgumentList '--verify' -WindowStyle Hidden -Wait -PassThru
if ($verification.ExitCode -ne 0) { throw 'Setup payload self-verification failed.' }
$setupHash = (Get-FileHash -LiteralPath $OutputPath).Hash
"$setupHash  $(Split-Path -Leaf $OutputPath)" | Set-Content -LiteralPath "$OutputPath.sha256" -Encoding ASCII
Write-Host "PASS: single-file setup created: $OutputPath ($setupHash)"
