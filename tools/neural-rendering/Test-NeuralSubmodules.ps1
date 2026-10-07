[CmdletBinding()]
param([string]$Case = '*')

. (Join-Path $PSScriptRoot 'Common.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('neuraldoom-submodules-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$failed = [Collections.Generic.List[string]]::new()
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    if ($Name -notlike $Case) { return }
    try { & $Body; Write-Host "PASS: $Name" } catch { $failed.Add($Name); Write-Host "FAIL: ${Name}: $($_.Exception.Message)" }
}
function Initialize-FixtureRepo {
    param([string]$Name)
    $path = Join-Path $fixture $Name
    Invoke-NativeChecked git @('init', '--quiet', $path)
    Invoke-NativeChecked git @('-C', $path, 'config', 'user.name', 'Fixture')
    Invoke-NativeChecked git @('-C', $path, 'config', 'user.email', 'fixture@example.invalid')
    Invoke-NativeChecked git @('-C', $path, 'config', 'core.autocrlf', 'false')
    $Name | Set-Content -LiteralPath (Join-Path $path 'source.txt')
    Invoke-NativeChecked git @('-C', $path, 'add', 'source.txt')
    Invoke-NativeChecked git @('-C', $path, 'commit', '--quiet', '-m', 'fixture')
    return $path
}
function Invoke-SubmoduleCheck {
    param([string]$Root)
    # Other host prerequisites may be absent on CI. Inspect the real submodule
    # result even when those unrelated required checks reject the fixture root.
    (& {
        try { & (Join-Path $PSScriptRoot 'Check-Prerequisites.ps1') -RepoRoot $Root }
        catch { Write-Output $_.Exception.Message }
    } *>&1 | Out-String -Width 4096)
}
function Expect-ModulesOK {
    param([string]$Root, [int]$Count)
    $text = Invoke-SubmoduleCheck $Root
    if ($text -notmatch "Git submodules\s+yes\s+OK\s+$Count declared submodule") { throw "Expected $Count initialized declared modules: $text" }
}
function Expect-ModulesMissing {
    param([string]$Root, [string]$Detail)
    $text = Invoke-SubmoduleCheck $Root
    if ($text -notmatch 'Git submodules\s+yes\s+MISSING' -or $text -notmatch $Detail) { throw "Expected module rejection ($Detail): $text" }
}
try {
    $leaf = Initialize-FixtureRepo 'leaf'
    $dependency = Initialize-FixtureRepo 'dependency'
    Invoke-NativeChecked git @('-C', $dependency, '-c', 'protocol.file.allow=always', 'submodule', 'add', '--quiet', $leaf, 'nested')
    Invoke-NativeChecked git @('-C', $dependency, 'commit', '--quiet', '-am', 'nested dependency')
    $project = Initialize-FixtureRepo 'project'
    Invoke-NativeChecked git @('-C', $project, '-c', 'protocol.file.allow=always', 'submodule', 'add', '--quiet', $dependency, 'deps/module')
    Invoke-NativeChecked git @('-C', $project, '-c', 'protocol.file.allow=always', 'submodule', 'add', '--quiet', $leaf, 'deps/leaf')
    Invoke-NativeChecked git @('-C', $project, 'commit', '--quiet', '-am', 'project dependency')
    Invoke-NativeChecked git @('-C', $project, '-c', 'protocol.file.allow=always', 'submodule', 'update', '--init', '--recursive', '--quiet')
    $module = Join-Path $project 'deps/module'
    $nested = Join-Path $module 'nested'
    Test-Case 'recursive-initialized-graph' { Expect-ModulesOK $project 3 }
    Test-Case 'ignored-archive-does-not-add-dependencies' {
        $archive = Join-Path $project 'archive/old-checkout'
        New-Item -ItemType Directory -Path $archive -Force | Out-Null
        '/archive/' | Set-Content -LiteralPath (Join-Path $project '.git/info/exclude')
        "[submodule `"obsolete`"]`n    path = missing-dependency`n    url = unused" | Set-Content -LiteralPath (Join-Path $archive '.gitmodules')
        Expect-ModulesOK $project 3
    }
    Test-Case 'absent-gitmodules-declarations-reported' {
        $modules = Join-Path $project '.gitmodules'
        $original = [IO.File]::ReadAllBytes($modules)
        try {
            Invoke-NativeChecked git @('-C', $project, 'submodule', 'deinit', '--force', '--quiet', '--all')
            Remove-Item -LiteralPath $modules
            Expect-ModulesMissing $project 'deps[/\\]module.*missing .gitmodules path declaration'
        } finally {
            [IO.File]::WriteAllBytes($modules, $original)
            Invoke-NativeChecked git @('-C', $project, '-c', 'protocol.file.allow=always', 'submodule', 'update', '--init', '--recursive', '--quiet')
        }
    }
    Test-Case 'empty-gitmodules-declarations-reported' {
        $modules = Join-Path $project '.gitmodules'
        $original = [IO.File]::ReadAllBytes($modules)
        try {
            Invoke-NativeChecked git @('-C', $project, 'submodule', 'deinit', '--force', '--quiet', '--all')
            '' | Set-Content -LiteralPath $modules
            Expect-ModulesMissing $project 'deps[/\\]module.*missing .gitmodules path declaration'
        } finally {
            [IO.File]::WriteAllBytes($modules, $original)
            Invoke-NativeChecked git @('-C', $project, '-c', 'protocol.file.allow=always', 'submodule', 'update', '--init', '--recursive', '--quiet')
        }
    }
    Test-Case 'missing-one-gitmodules-declaration-reported' {
        $modules = Join-Path $project '.gitmodules'
        $original = [IO.File]::ReadAllBytes($modules)
        try {
            Invoke-NativeChecked git @('-C', $project, 'submodule', 'deinit', '--force', '--quiet', 'deps/module')
            Invoke-NativeChecked git @('config', '--file', $modules, '--remove-section', 'submodule.deps/module')
            Expect-ModulesMissing $project 'deps[/\\]module.*missing .gitmodules path declaration'
        } finally {
            [IO.File]::WriteAllBytes($modules, $original)
            Invoke-NativeChecked git @('-C', $project, '-c', 'protocol.file.allow=always', 'submodule', 'update', '--init', '--recursive', '--quiet')
        }
    }
    Test-Case 'uninitialized-empty-folder-cannot-borrow-parent-repo' {
        Invoke-NativeChecked git @('-C', $project, 'submodule', 'deinit', '--force', '--quiet', 'deps/module')
        Expect-ModulesMissing $project 'deps[/\\]module.*uninitialized'
        Invoke-NativeChecked git @('-C', $project, '-c', 'protocol.file.allow=always', 'submodule', 'update', '--init', '--recursive', '--quiet')
    }
    Test-Case 'missing-recursive-dependency-reported' {
        Invoke-NativeChecked git @('-C', $module, 'submodule', 'deinit', '--force', '--quiet', 'nested')
        Expect-ModulesMissing $project 'deps[/\\]module[/\\]nested.*uninitialized'
        Invoke-NativeChecked git @('-C', $project, '-c', 'protocol.file.allow=always', 'submodule', 'update', '--init', '--recursive', '--quiet')
    }
    Test-Case 'corrupt-submodule-git-pointer-reported' {
        $pointer = Join-Path $module '.git'
        $original = [IO.File]::ReadAllBytes($pointer)
        $attributes = [IO.File]::GetAttributes($pointer)
        try {
            [IO.File]::SetAttributes($pointer, [IO.FileAttributes]::Normal)
            'gitdir: nonexistent-module-database' | Set-Content -LiteralPath $pointer
            Expect-ModulesMissing $project 'deps[/\\]module.*(foreign repository|uninitialized)'
        } finally {
            [IO.File]::WriteAllBytes($pointer, $original)
            [IO.File]::SetAttributes($pointer, $attributes)
        }
    }
    Test-Case 'malformed-gitmodules-reported' {
        $modules = Join-Path $project '.gitmodules'
        $original = [IO.File]::ReadAllBytes($modules)
        try {
            '[broken config' | Set-Content -LiteralPath $modules
            Expect-ModulesMissing $project 'invalid .gitmodules'
        } finally { [IO.File]::WriteAllBytes($modules, $original) }
    }
    Test-Case 'wrong-submodule-revision-reported' {
        $old = (& git -C $module rev-parse HEAD).Trim()
        Invoke-NativeChecked git @('-C', $module, 'submodule', 'deinit', '--force', '--quiet', 'nested')
        Invoke-NativeChecked git @('-C', $module, 'checkout', '--quiet', 'HEAD^')
        Expect-ModulesMissing $project 'deps[/\\]module.*revision mismatch'
        Invoke-NativeChecked git @('-C', $module, 'checkout', '--quiet', $old)
        Invoke-NativeChecked git @('-C', $project, '-c', 'protocol.file.allow=always', 'submodule', 'update', '--init', '--recursive', '--quiet')
    }
    Test-Case 'foreign-submodule-repository-rejected' {
        Invoke-NativeChecked git @('-C', $project, 'submodule', 'deinit', '--force', '--quiet', 'deps/module')
        $foreign = Initialize-FixtureRepo 'foreign'
        Invoke-NativeChecked git @('clone', '--quiet', '--no-hardlinks', $foreign, $module)
        Expect-ModulesMissing $project 'deps[/\\]module.*(foreign repository|revision mismatch)'
    }
    Test-Case 'repo-root-cannot-borrow-parent-repo' {
        $empty = Join-Path $project 'untracked-empty-folder'
        New-Item -ItemType Directory -Path $empty | Out-Null
        Expect-ModulesMissing $empty 'repository root'
    }
    Test-Case 'repo-with-no-declarations-is-valid' { Expect-ModulesOK $leaf 0 }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'neuraldoom-submodules-*') { throw 'Unsafe fixture cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
if ($failed.Count) { throw "Submodule failures: $($failed -join ', ')" }
