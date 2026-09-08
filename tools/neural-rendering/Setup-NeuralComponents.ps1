# Installation-time acquisition only. No third-party binary belongs in our ZIP or Git.
. (Join-Path $PSScriptRoot 'Setup-Dependencies.ps1')
. (Join-Path $PSScriptRoot 'EmbeddedNR.ps1')

function Test-SetupNvidiaDll {
    param([string]$Path, [string]$RequiredHash)
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'Selected runtime is not a Windows DLL.' }
        $stream.Position = 0x3c; $offset = $reader.ReadUInt32()
        if ($offset -gt $stream.Length - 26) { throw 'Invalid selected DLL header.' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'Select a Windows x64 NVIDIA DLL.' }
        $stream.Position = $offset + 22
        if (($reader.ReadUInt16() -band 0x2000) -eq 0) { throw 'Selected file is not a DLL.' }
    } finally { $reader.Dispose() }
    if ($RequiredHash) {
        if ((Get-FileHash -LiteralPath $Path).Hash -ne $RequiredHash) {
            throw 'Select the supported RHI NR 310.8.SF-v2 DLL, or clear the NR field for automatic download. Other NR versions failed startup validation.'
        }
        return
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=NVIDIA Corporation(?:,|$)') {
        throw 'The selected DLL must have a valid NVIDIA publisher signature.'
    }
}

function Expand-SetupNeuralComponent {
    param($Component, [string]$Cache)
    $headers = @{}
    if ($Component.PSObject.Properties['referer']) { $headers.Referer = $Component.referer }
    Write-SetupStatus "Preparing $($Component.id)..."
    $archive = Get-SetupDownload -Uri $Component.url -Destination (Join-Path $Cache $Component.file) -Sha256 $Component.sha256 -Bytes $Component.bytes -Headers $headers
    # ReShade's official EXE is a ZIP SFX. Never execute its installer; expose the
    # pinned embedded ZIP to .NET (which does not understand this SFX directly).
    if ($Component.PSObject.Properties['zipOffset']) {
        $zipPath = Join-Path $Cache ($Component.file + '.zip')
        $inputStream = [IO.File]::OpenRead($archive); $outputStream = [IO.File]::Create($zipPath)
        try { $inputStream.Position = $Component.zipOffset; $inputStream.CopyTo($outputStream) }
        finally { $outputStream.Dispose(); $inputStream.Dispose() }
        $archive = $zipPath
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    $result = @{}
    try {
        foreach ($member in $Component.members) {
            if ([IO.Path]::GetFileName($member.name) -ne $member.name -or $member.name -match '[:/\\]') { throw 'Invalid component destination.' }
            $matches = @($zip.Entries | Where-Object FullName -CEQ $member.path)
            if ($matches.Count -ne 1) { throw "Missing or duplicate component member: $($member.path)" }
            $path = Join-Path $Cache ($Component.id + '-' + $member.name)
            $inputStream = $matches[0].Open(); $outputStream = [IO.File]::Create($path)
            try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose(); $inputStream.Dispose() }
            if ($member.PSObject.Properties['sha256'] -and (Get-FileHash -LiteralPath $path).Hash -ne $member.sha256) { throw "Component member checksum failed: $($member.name)" }
            $result[$member.name] = $path
        }
    } finally { $zip.Dispose() }
    return $result
}

function Install-SetupNeuralComponents {
    param([string]$RepoRoot, [ValidateSet('Native', 'DLAA', 'NR')][string]$Profile,
        [string]$DlssDllPath, [string]$NRDllPath)
    if ($Profile -eq 'Native') { return }
    if ($Profile -eq 'NR' -and (Test-Path -LiteralPath (Join-Path $RepoRoot 'dxgi.dll'))) { throw 'Remove the existing DXGI proxy before installing the engine-loaded NR profile.' }
    $cache = Join-Path $RepoRoot '.neuraldoom-cache/neural'
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $catalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'neural-components.json') -Raw | ConvertFrom-Json
    $files = @{}; $sources = @()
    foreach ($component in $catalog.components) {
        if ($Profile -eq 'DLAA' -and $component.id -notin @('streamline', 'dlss')) { continue }
        $local = if ($component.id -eq 'dlss') { $DlssDllPath } elseif ($component.id -eq 'nr') { $NRDllPath } else { $null }
        if ($local) {
            $local = (Resolve-Path -LiteralPath $local).Path
            if ([IO.Path]::GetFileName($local) -ine $component.members[0].name) { throw "Select $($component.members[0].name) for $($component.id)." }
            $requiredHash = if ($component.id -eq 'nr') { $component.members[0].sha256 } else { $null }
            Test-SetupNvidiaDll -Path $local -RequiredHash $requiredHash
            # Snapshot the selected input before any destination is replaced.
            $snapshot = Join-Path $cache ('selected-' + $component.members[0].name)
            Copy-Item -LiteralPath $local -Destination $snapshot -Force
            Test-SetupNvidiaDll -Path $snapshot -RequiredHash $requiredHash
            $files[$component.members[0].name] = $snapshot
            $sources += @{ id = $component.id; source = $(if ($requiredHash) { 'local RHI DLL matching tested pin' } else { 'local NVIDIA-signed DLL' }); sha256 = (Get-FileHash -LiteralPath $snapshot).Hash }
        } else {
            $extracted = Expand-SetupNeuralComponent -Component $component -Cache $cache
            foreach ($name in $extracted.Keys) { $files[$name] = $extracted[$name] }
            $sources += @{ id = $component.id; source = $component.url; sha256 = $component.sha256 }
        }
    }
    $build = Join-Path $RepoRoot 'build-streamline/Release'
    if (-not (Test-Path -LiteralPath (Join-Path $build 'neuralDoom.exe'))) { throw 'The package is missing its neural engine.' }
    $notices = Join-Path $RepoRoot 'third-party-notices'
    New-Item -ItemType Directory -Path $notices -Force | Out-Null
    foreach ($name in $files.Keys) {
        $targets = if ($name.EndsWith('.txt')) { @(Join-Path $notices $name) }
            elseif ($name -like 'sl.*.dll' -or $name -eq 'nvngx_dlss.dll') {
                @(Join-Path $build $name); if ($Profile -eq 'NR') { Join-Path $RepoRoot $name }
            } else { @(Join-Path $RepoRoot $name) }
        foreach ($target in $targets) {
            Copy-Item -LiteralPath $files[$name] -Destination $target -Force
            if ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $files[$name]).Hash) { throw "Installed component verification failed: $name" }
        }
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../docs/neural-rendering/THIRD_PARTY_AND_LEGAL.md') -Destination (Join-Path $notices 'component-provenance.md') -Force
    $sources | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $notices 'installed-components.json') -Encoding UTF8
    if ($Profile -eq 'NR') {
        $ini = Join-Path $RepoRoot 'reshade.ini'
        $text = if (Test-Path -LiteralPath $ini) { [IO.File]::ReadAllText($ini) } else {
            "[INPUT]`r`nKeyOverlay=36,0,0,0`r`nKeyEffects=0,0,0,0`r`n[RenoDX.DLSS5]`r`n"
        }
        # Existing appearance controls survive; only the input/hook contract is fixed.
        if ($text -notmatch '(?m)^\[RenoDX\.DLSS5\]') { $text += "`r`n[RenoDX.DLSS5]`r`n" }
        [IO.File]::WriteAllText($ini, (Get-NeuralNRFullResolutionConfig -Text $text), (New-Object Text.UTF8Encoding $false))
        $null = Get-NeuralEmbeddedNRState -RepoRoot $RepoRoot -BuildExecutable (Join-Path $build 'neuralDoom.exe')
    }
    Write-SetupStatus "$Profile components verified. Full-resolution rendering is ready."
}
