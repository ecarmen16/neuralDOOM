"""Regression checks for tracked-source and release-payload privacy gates."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('packager', root / 'tools/neural-rendering/Build-InternalPackage.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
profile = '\\'.join(['C:', 'Users', 'privacy-fixture', 'source', 'file.cpp'])
for value in (profile, profile.replace('\\', '/').upper()):
    for encoding in ('utf-8', 'utf-16-le'):
        assert packager.has_personal_profile_path(value.encode(encoding)), encoding
for value in ('%USERPROFILE%/Saved Games', '\\'.join(['C:', 'Users', '<profile>', 'source']), 'Z:/neo/file.cpp'):
    assert not packager.has_personal_profile_path(value.encode())
print('PASS: release privacy gate catches both separators/cases and UTF-16; permits placeholders and neutral build paths.')

powershell = Path(os.environ['WINDIR']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
audit = root / 'tools/neural-rendering/Test-NeuralDoom-PublicSource.ps1'
with tempfile.TemporaryDirectory(prefix='neuraldoom-privacy-') as temporary:
    fixture = Path(temporary)
    subprocess.run(['git', 'init', '-q', str(fixture)], check=True)
    document = fixture / 'example.md'

    def stage(text):
        document.write_text(text)
        subprocess.run(['git', '-C', str(fixture), 'add', 'example.md'], check=True)

    def check(expected, staged):
        args = [str(powershell), '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(audit), '-RepoRoot', str(fixture), '-AllowDirty']
        if staged:
            args.append('-Staged')
        result = subprocess.run(args, capture_output=True, text=True)
        assert result.returncode == expected, result.stdout + result.stderr
        assert 'privacy-fixture' not in result.stdout, 'Audit printed private matching content'

    for value in (profile, profile.replace('\\', '/').upper()):
        stage(value)
        document.write_text('Sanitized working copy')
        check(1, True)
        check(0, False)
    stage('%USERPROFILE%/Saved Games')
    check(0, True)
print('PASS: staged index remains checked after working-copy cleanup; privacy findings report location only.')
