"""Build an allowlisted native RTX Release ZIP with corresponding source.

Requires clean, matching source/build commits. Never copies a game directory.
"""
import argparse
import hashlib
import io
import json
import pathlib
import subprocess
import struct
import zipfile


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])


def digest(data):
    return hashlib.sha256(data).hexdigest().upper()


def pe_imports(data):
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise RuntimeError('Invalid executable')
    sections, optional_size = struct.unpack_from('<H', data, pe + 6)[0], struct.unpack_from('<H', data, pe + 20)[0]
    optional = pe + 24
    if struct.unpack_from('<H', data, optional)[0] != 0x20b:
        raise RuntimeError('Expected a Windows x64 executable')
    table = optional + optional_size

    def offset(rva):
        for i in range(sections):
            size, start, raw_size, raw = struct.unpack_from('<IIII', data, table + i * 40 + 8)
            if start <= rva < start + max(size, raw_size):
                return raw + rva - start
        raise RuntimeError('Invalid import RVA')

    position = offset(struct.unpack_from('<I', data, optional + 120)[0])
    names = []
    while any(data[position:position + 20]):
        name = offset(struct.unpack_from('<I', data, position + 12)[0])
        names.append(data[name:data.index(b'\0', name)].decode('ascii'))
        position += 20
    return names


def source_entries(root, revision):
    archive = git(root, 'archive', '--format=zip', revision)
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        for entry in z.infolist():
            if entry.is_dir():
                continue
            # Unused upstream prebuilt tools/import libs are not corresponding source.
            if pathlib.PurePosixPath(entry.filename).suffix.lower() in {'.exe', '.dll', '.lib', '.pdb'}:
                continue
            yield entry.filename, z.read(entry)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', type=pathlib.Path, required=True)
    ap.add_argument('--game', type=pathlib.Path, required=True)
    ap.add_argument('--output', type=pathlib.Path, required=True)
    args = ap.parse_args()
    source, game = args.source.resolve(), args.game.resolve()
    revision = git(source, 'rev-parse', 'HEAD').decode().strip()
    for root in (source, game):
        if git(root, 'status', '--porcelain').strip():
            raise RuntimeError(f'Commit or preserve outstanding edits before packaging: {root}')
        if git(root, 'rev-parse', 'HEAD').decode().strip() != revision:
            raise RuntimeError('Source and build checkout commits differ')
    manifest = json.loads((game / 'build-rt/neuraldoom-build-Release.json').read_text(encoding='utf-8-sig'))
    if manifest['commit'] != revision or manifest['dirty'] or manifest['configuration'] != 'Release':
        raise RuntimeError('Rebuild Release from the clean matching source commit')
    if manifest['features']['streamline'] != 'OFF' or manifest['features']['rayTracing'] != 'ON':
        raise RuntimeError('Only the SDK-free native RTX build is approved for this package')
    exe = pathlib.Path(manifest['executable']).read_bytes()
    if digest(exe) != manifest['sha256'].upper():
        raise RuntimeError('Executable differs from build manifest')
    # Catch the current development configuration accidentally entering a release.
    imports = pe_imports(exe)
    if any(name.lower() in {'msvcp140d.dll', 'vcruntime140d.dll', 'vcruntime140_1d.dll', 'ucrtbased.dll'} or
           name.lower().startswith(('nvngx', 'sl.')) for name in imports):
        raise RuntimeError('Debug CRT or NVIDIA runtime dependency in shipping executable')
    files = dict(source_entries(source, revision))
    submodules = []
    for line in git(game, 'submodule', 'status', '--recursive').decode().splitlines():
        if not line or line[0] != ' ':
            raise RuntimeError('Submodule is missing or differs from its recorded revision')
        commit, name, *_ = line[1:].split()
        submodules.append({'path': name, 'commit': commit})
        for path, data in source_entries(game / name, commit):
            files[f'{name}/{path}'] = data
    files['build-rt/Release/neuralDoom.exe'] = exe
    for shader in manifest['shaders']:
        path = pathlib.PurePosixPath(shader['path'])
        if path.is_absolute() or '..' in path.parts or path.suffix != '.dxil':
            raise RuntimeError('Invalid shader manifest path')
        data = (game / path).read_bytes()
        if digest(data) != shader['sha256'].upper():
            raise RuntimeError(f'Shader mismatch: {path}')
        files[str(path)] = data
    files['SOURCE_REVISION.txt'] = (revision + '\n' + ''.join(f"{m['commit']} {m['path']}\n" for m in submodules)).encode()
    for name in files:
        path = pathlib.PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or path.suffix.lower() in {'.resources', '.resource', '.pk4', '.dll', '.addon64', '.pdb'}:
            raise RuntimeError(f'Non-distributable or unsafe package entry: {name}')
    portable = dict(manifest)
    portable.pop('builtAt', None)
    portable['executable'] = 'build-rt/Release/neuralDoom.exe'
    portable['submodules'] = submodules
    portable['imports'] = imports
    portable['files'] = [{'path': name, 'sha256': digest(data)} for name, data in sorted(files.items())]
    files['internal-package.json'] = (json.dumps(portable, indent=2) + '\n').encode()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Never overwrite a previously handed-out artifact.
    with args.output.open('xb') as out, zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for name, data in sorted(files.items()):
            z.writestr(name, data)
    with zipfile.ZipFile(args.output) as z:
        if z.testzip() is not None:
            raise RuntimeError('ZIP integrity check failed')
    checksum = digest(args.output.read_bytes())
    args.output.with_suffix('.zip.sha256').write_text(f'{checksum}  {args.output.name}\n', encoding='ascii')
    print(f'PASS: {len(files)} files, source {revision}, native RTX Release, ZIP SHA256 {checksum}')


if __name__ == '__main__':
    main()
