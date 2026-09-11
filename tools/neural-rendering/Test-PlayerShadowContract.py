# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate player-shadow SRVs against compiled DXIL and ordered NVRHI bindings."""
import argparse
import pathlib
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--dxc', required=True)
parser.add_argument('--repo-root', type=pathlib.Path, default=pathlib.Path('.'))
args = parser.parse_args()
source = (args.repo_root / 'neo/renderer/RayTracingDiagnostic.cpp').read_text()

def sequences(kind):
    result = []
    for body in re.findall(r'\w+\.bindings\s*=\s*\{(.*?)\};', source, re.S):
        pairs = re.findall(r'nvrhi::Binding'+kind+r'Item::(\w+)\(\s*(\d+)', body)
        pairs = [(name.replace('VolatileConstantBuffer', 'ConstantBuffer'), slot) for name, slot in pairs]
        if ('StructuredBuffer_SRV', '12') in pairs:
            result.append(pairs)
    return result

layouts = sequences('Layout')
bindings = sequences('Set')
assert len(layouts) == len(bindings) == 4, (len(layouts), len(bindings))
for binding in bindings:
    assert binding in layouts, f'Policy binding order does not match any NVRHI layout: {binding}'
for name in ('ray_query', 'contact_shadows', 'diffuse_bounce', 'reflections'):
    binary = args.repo_root / f'base/renderprogs2/dxil/rt/{name}.cs.dxil'
    assembly = subprocess.check_output([args.dxc, '-dumpbin', str(binary)], text=True)
    assert re.search(r'^; RayShadowPolicies\s+.*\st12\s+1\s*$', assembly, re.M), name
    if name == 'contact_shadows':
        assert re.search(r'} Parameters;\s*; Offset:\s*0 Size:\s*144\b', assembly), 'Contact constant layout'
print('PASS: four ordered NVRHI policy bindings, four compiled t12 SRVs, 144-byte contact constants')
