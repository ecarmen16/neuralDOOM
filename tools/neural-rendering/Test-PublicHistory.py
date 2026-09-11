"""Read-only history privacy/artifact audit; report locations, never matched text.

Complements a secret scanner. Does not rewrite history, sanitize author credits,
or determine whether third-party content is licensed for redistribution.
"""
import argparse
import json
import pathlib
import re
import subprocess


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])


def audit(root, refs, upstream):
    inventory = {}
    for row in git(root, 'rev-list', '--objects', *refs).splitlines():
        oid, _, path = row.partition(b' ')
        inventory[oid.decode()] = path.decode('utf-8', 'replace')
    inherited = {row.split(b' ', 1)[0].decode() for row in
                 git(root, 'rev-list', '--objects', upstream).splitlines()} if upstream else set()
    windows = re.compile(rb'''(?i)\b[a-z]:[\\/]+Users[\\/]+(?![<%${])[^\\/\s<>"']+''')
    unix = re.compile(rb'''/(?:home|Users)/(?![<%${])[^/\s<>"']+/''')
    forbidden = re.compile(r'(?i)(\.(?:resources?|pk4|rdc|nv-gpudmp|addon64)$|'
                           r'(^|/)(?:captures|releases|neural-local|local-proprietary|local-research|'
                           r'\.neuraldoom-cache|settings-snapshots|mod_D3HDP_Lite)/|'
                           r'(^|/)(?:nvngx_[^/]*\.dll|sl\.[^/]*\.dll|dxgi\.dll|neuraldoom-reshade64\.dll)$)')
    findings = []
    examined = 0
    reader = subprocess.Popen(['git', '-C', str(root), 'cat-file', '--batch'],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        for oid, path in inventory.items():
            reader.stdin.write((oid + '\n').encode()); reader.stdin.flush()
            header = reader.stdout.readline().split()
            if len(header) != 3:
                raise RuntimeError('Missing Git object during audit')
            data = reader.stdout.read(int(header[2]))
            if len(data) != int(header[2]) or reader.stdout.read(1) != b'\n':
                raise RuntimeError('Incomplete Git object during audit')
            kind = header[1]
            if kind not in (b'blob', b'commit'):
                continue
            examined += 1
            # Authorship is attribution, not a path leak. Scan commit messages only.
            content = data.partition(b'\n\n')[2] if kind == b'commit' else data
            categories = []
            if kind == b'blob' and forbidden.search(path):
                categories.append('local-artifact-path')
            flattened = content.replace(b'\0', b'')
            if windows.search(flattened):
                categories.append('personal-windows-path')
            if unix.search(flattened):
                categories.append('personal-unix-path-review')
            for category in categories:
                findings.append({'object': oid, 'path': path or '(commit message)',
                                 'category': category, 'inherited': oid in inherited})
    finally:
        reader.stdin.close(); reader.stdout.close()
        if reader.wait() != 0:
            raise RuntimeError('Git object reader failed')
    return {'schemaVersion': 1, 'refs': refs, 'upstream': upstream,
            'objectsExamined': examined, 'findings': findings}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[2])
    parser.add_argument('--upstream', help='Known upstream commit, used only to classify inherited findings')
    parser.add_argument('--refs', nargs='+', default=['--all'])
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    report = audit(args.repo, args.refs, args.upstream)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    added = sum(not row['inherited'] for row in report['findings'])
    print(f"History audit: {report['objectsExamined']} objects; {added} downstream and "
          f"{len(report['findings']) - added} inherited locations require review. No matching content printed.")
    raise SystemExit(1 if report['findings'] else 0)
