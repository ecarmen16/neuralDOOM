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
    foreach ($name in @('InternalSetup.cs', 'Bootstrap-InternalSetup.ps1')) {
        $record = @($manifest.files | Where-Object path -EQ "tools/neural-rendering/$name")
        if ($record.Count -ne 1 -or (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash -ne $record[0].sha256) { throw 'Bootstrap source differs from the packaged corresponding source.' }
    }
} finally { $zip.Dispose() }
$hashFile = Join-Path $stage 'checksum.txt'
(Get-FileHash -LiteralPath $PackagePath).Hash | Set-Content -LiteralPath $hashFile -Encoding ASCII
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows .NET Framework C# compiler is missing.' }
& $compiler /nologo /target:exe /platform:x64 /optimize+ ("/out:" + $OutputPath) ("/resource:" + $PackagePath + ',Payload') ("/resource:" + (Join-Path $PSScriptRoot 'Bootstrap-InternalSetup.ps1') + ',Bootstrap') ("/resource:" + $hashFile + ',Checksum') (Join-Path $PSScriptRoot 'InternalSetup.cs')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputPath)) { throw 'Setup bootstrap compilation failed.' }
& $OutputPath --verify
if ($LASTEXITCODE -ne 0) { throw 'Setup payload self-verification failed.' }
$setupHash = (Get-FileHash -LiteralPath $OutputPath).Hash
"$setupHash  $(Split-Path -Leaf $OutputPath)" | Set-Content -LiteralPath "$OutputPath.sha256" -Encoding ASCII
Write-Host "PASS: single-file setup created: $OutputPath ($setupHash)"
