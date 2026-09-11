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

with tempfile.TemporaryDirectory(prefix='neuraldoom-settings-privacy-') as temporary:
    for index, name in enumerate(('settings-snapshots/personal.zip', 'base/D3BFGConfig.cfg',
                                  'reshade.ini', 'ReShadePreset.ini', 'profile.bin',
                                  '.neuraldoom-snapshot-interrupted.tmp')):
        fixture = Path(temporary) / str(index)
        subprocess.run(['git', 'init', '-q', str(fixture)], check=True)
        target = fixture / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text('private settings fixture')
        subprocess.run(['git', '-C', str(fixture), 'add', '-f', name], check=True)
        result = subprocess.run([str(powershell), '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                 '-File', str(audit), '-RepoRoot', str(fixture), '-AllowDirty', '-Staged'],
                                capture_output=True, text=True)
        assert result.returncode == 1, name
print('PASS: forced additions of personal settings, snapshots and interrupted ZIPs are rejected.')

history_spec = importlib.util.spec_from_file_location('history_audit', root / 'tools/neural-rendering/Test-PublicHistory.py')
history_audit = importlib.util.module_from_spec(history_spec)
history_spec.loader.exec_module(history_audit)
with tempfile.TemporaryDirectory(prefix='neuraldoom-history-privacy-') as temporary:
    fixture = Path(temporary)
    subprocess.run(['git', 'init', '-q', str(fixture)], check=True)
    def commit_fixture():
        subprocess.run(['git', '-C', str(fixture), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(fixture), '-c', 'user.name=Privacy Fixture',
                        '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Fixture'], check=True)
    document = fixture / 'example.md'
    document.write_text('Clean baseline')
    commit_fixture()
    baseline = history_audit.git(fixture, 'rev-parse', 'HEAD').decode().strip()
    document.write_text(profile)
    artifact = fixture / 'private.resources'
    artifact.write_bytes(b'fixture')
    commit_fixture()
    document.write_text('Clean current tree')
    artifact.unlink()
    commit_fixture()
    report = history_audit.audit(fixture, ['--all'], baseline)
    assert {row['category'] for row in report['findings']} == {'personal-windows-path', 'local-artifact-path'}
    assert all(not row['inherited'] for row in report['findings'])
    assert 'privacy-fixture' not in str(report)
print('PASS: history audit finds removed private paths/artifacts without exposing matching content.')
