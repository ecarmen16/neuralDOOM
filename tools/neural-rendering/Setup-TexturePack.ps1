# Install publisher-provided content locally; never include it in release payloads.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Setup-Dependencies.ps1')
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem

function Test-D3HDPArchive {
    param([string]$Path)
    $file = Get-Item -LiteralPath $Path
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Texture archive must be a regular local file.' }
    if ($file.Length -eq 2143217579 -and (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq 'E72ABB1C6C8C69FB28913D33709B298AC9553D4F52B10B0D02776BF00589BC4F') { return }
    if ($file.Length -eq 2143408902 -and (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq '513539D158C29B3A5C48E14C73FB8968427AD2644FD75F3E2C39991A589E813C') { return }
    throw 'D3HDP ZIP does not match either inspected publisher release. Select the original D3HDP_BFG_Lite.zip; do not repackage it.'
}

function Get-D3HDPArchive {
    param([string]$RepoRoot, [string]$ArchivePath)
    if ($ArchivePath) { Test-D3HDPArchive $ArchivePath; return $ArchivePath }
    $cache = Get-SetupSafePath $RepoRoot '.neuraldoom-cache/D3HDP_BFG_Lite.zip'
    if (Test-Path -LiteralPath $cache) { Test-D3HDPArchive $cache; return $cache }
    New-Item -ItemType Directory -Path (Split-Path -Parent $cache) -Force | Out-Null
    $partial = Get-SetupSafePath $RepoRoot '.neuraldoom-cache/D3HDP_BFG_Lite.zip.partial'
    $uri = [uri]'https://www.moddb.com/downloads/start/265648'
    Write-SetupStatus 'Downloading D3HDP BFG Lite by H3llBaron (2.14 GB)...'
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $uri -OutFile $partial -UseBasicParsing -MaximumRedirection 10 -ErrorAction Stop
        if ((Get-Item -LiteralPath $partial).Length -lt 1MB) {
            $html = Get-Content -LiteralPath $partial -Raw
            $match = [regex]::Match($html, '(?i)href=["''][^"'']*(?<path>/downloads/mirror/265648/[^"'']+)["'']')
            if (-not $match.Success) { throw 'No publisher download mirror was returned.' }
            $mirror = [uri]::new($uri, [Net.WebUtility]::HtmlDecode($match.Groups['path'].Value))
            Invoke-WebRequest -Uri $mirror -OutFile $partial -UseBasicParsing -MaximumRedirection 10 -ErrorAction Stop
        }
        Test-D3HDPArchive $partial
        Move-Item -LiteralPath $partial -Destination $cache
        return $cache
    } catch {
        throw 'The texture pack could not be downloaded or verified. ModDB may require a browser download. Download D3HDP_BFG_Lite.zip from https://www.moddb.com/mods/d3hdp-bfg-lite/downloads/d3hdp-bfg-lite, then rerun setup and select that ZIP on the Texture pack page. You can also turn off the optional pack.'
    } finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    }
}

function Install-SetupTexturePack {
    param([string]$RepoRoot, [string]$ArchivePath)
    . (Join-Path $PSScriptRoot 'Install-Lifecycle.ps1')
    Assert-SetupInstallRoot $RepoRoot -Existing
    $null = @(Get-SetupFiles $RepoRoot)
    $archive = Get-D3HDPArchive -RepoRoot $RepoRoot -ArchivePath $ArchivePath
    Write-SetupStatus 'Verifying and preparing D3HDP textures and original credits...'
    $stage = Join-Path $RepoRoot ('.neuraldoom-cache/d3hdp-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    $loose = $null
    $outputs = @(); $seen = @{}; $readme = $false; $assetCount = 0; $expanded = [long]0
    try {
        $loosePath = Join-Path $stage 'zzz_neural_d3hdp_loose.pk4'
        $loose = [IO.Compression.ZipFile]::Open($loosePath, [IO.Compression.ZipArchiveMode]::Create)
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name -match '(^/|:|(^|/)\.\.(/|$))' -or $name -match '[\x00-\x1f]' -or $name -match '(^|/)[^/]*[. ](/|$)' -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Unsafe texture archive member.' }
            if ($seen.ContainsKey($name)) { throw 'Duplicate texture archive member.' }; $seen[$name] = $true
            $expanded += $entry.Length
            if ($expanded -gt 12GB) { throw 'Texture archive exceeds the supported expanded size.' }
            if ($name.EndsWith('/')) { continue }
            if ($name -notin @('Readme.txt', 'Readme.pdf') -and -not $name.StartsWith('mod_D3HDP_Lite/', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected texture archive member.' }
            if ($name -in @('Readme.txt', 'Readme.pdf')) {
                $target = 'notices/D3HDP-BFG-Lite/' + $name; $readme = $true
            } else {
                $relative = $name.Substring('mod_D3HDP_Lite/'.Length)
                if ($relative -match '^[^/]+\.pk4$') {
                    $target = 'base/zzz_neural_d3hdp_' + $relative
                    $assetCount++
                } elseif ($relative -match '(?i)(readme|credits|license|copying)' -and $relative -match '\.(txt|md|html|pdf)$') {
                    $target = 'notices/D3HDP-BFG-Lite/mod/' + $relative
                } elseif ($relative -match '^(textures|models|materials|skins|def|sound|particles|guis|fonts|env|lights|script|generated|maps|ui)/' -and $relative -notmatch '\.(exe|dll|bat|cmd|ps1|cfg)$') {
                    $out = $loose.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
                    $out.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                    $src = $entry.Open(); $dst = $out.Open()
                    try { $src.CopyTo($dst) } finally { $dst.Dispose(); $src.Dispose() }
                    $assetCount++; continue
                } elseif ($relative -match '^[^/]+\.(bat|cmd|cfg|txt)$') {
                    $target = 'notices/D3HDP-BFG-Lite/original-launchers/' + $relative
                } else { throw "Unsupported texture archive layout: $relative" }
            }
            $path = Join-Path $stage $target
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $path, $false)
            $outputs += @{ path = $target; source = $path }
        }
        $loose.Dispose(); $loose = $null
        if (-not $readme -or $assetCount -eq 0) { throw 'Texture archive lacks the original readme or usable content.' }
        $check = [IO.Compression.ZipFile]::OpenRead($loosePath)
        try { if ($check.Entries.Count) { $outputs += @{ path = 'base/zzz_neural_d3hdp_loose.pk4'; source = $loosePath } } } finally { $check.Dispose() }
        $outputs += @{ path = 'notices/D3HDP-BFG-Lite/Credits.md'; source = (Join-Path $PSScriptRoot '../../docs/neural-rendering/D3HDP_CREDITS.md') }
        foreach ($item in $outputs) {
            $item.sha256 = (Get-FileHash -LiteralPath $item.source).Hash
            $target = Get-SetupSafePath $RepoRoot $item.path
            if ((Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target).Hash -ne $item.sha256) { throw 'A different or modified D3HDP installation exists. Use a new empty install folder for this test.' }
        }
        foreach ($item in $outputs) {
            $target = Get-SetupSafePath $RepoRoot $item.path
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            if (-not (Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $item.source -Destination $target }
        }
        $manifest = @{ project = 'D3HDP BFG Lite'; author = 'H3llBaron and the Doom 3 modding community'; source = 'https://www.moddb.com/mods/d3hdp-bfg-lite/downloads/d3hdp-bfg-lite'; archiveSha256 = (Get-FileHash -LiteralPath $archive).Hash; files = @($outputs | ForEach-Object { @{ path = $_.path; sha256 = $_.sha256 } }) }
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $RepoRoot 'notices/D3HDP-BFG-Lite/installed.json') -Encoding UTF8
        Write-SetupStatus 'D3HDP installed. Original readme and credits: notices/D3HDP-BFG-Lite'
    } finally {
        if ($loose) { $loose.Dispose() }; $zip.Dispose()
        $prefix = [IO.Path]::GetFullPath((Join-Path $RepoRoot '.neuraldoom-cache')).TrimEnd('\') + '\'
        if ([IO.Path]::GetFullPath($stage).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
}
