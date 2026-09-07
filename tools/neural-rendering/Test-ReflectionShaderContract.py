#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check compiled reflection shader contracts without creating a GPU device."""
import argparse
from pathlib import Path
import re
import struct
import subprocess
import tempfile


def permutations(path):
    data = path.read_bytes()
    assert data[:4] == b"NVSP", f"Not a ShaderMake permutation bundle: {path}"
    result, offset = {}, 4
    while offset + 8 <= len(data):
        key_size, size = struct.unpack_from("<II", data, offset)
        offset += 8
        if size == 0:
            break
        assert offset + key_size + size <= len(data), f"Truncated bundle: {path}"
        key = data[offset:offset + key_size].decode("ascii")
        offset += key_size
        assert key not in result, f"Duplicate permutation: {key}"
        result[key] = data[offset:offset + size]
        offset += size
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True, help="Checkout containing compiled base/renderprogs2")
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--dxc", type=Path, required=True)
    args = parser.parse_args()
    shader_root = args.repo_root / "base/renderprogs2/dxil"
    source = (args.source_root / "neo/renderer/RenderProgs.cpp").read_text(encoding="utf-8")
    entries = [line for line in source.splitlines() if re.match(r'\s*\{ BUILTIN_AMBIENT_(?:LIGHTING|LIGHTGRID)_IBL', line)]
    assert len(entries) == 16, "Expected eight baseline and eight material-capture programs"
    bundles, dumps = {}, {}
    lookup_count = 0
    with tempfile.TemporaryDirectory(prefix="neuraldoom-reflection-contract-") as directory:
        binary = Path(directory) / "permutation.dxil"

        def dump(data):
            if data not in dumps:
                binary.write_bytes(data)
                dumps[data] = subprocess.check_output([str(args.dxc), "-dumpbin", str(binary)], text=True)
            return dumps[data]

        for line in entries:
            name = re.search(r'"(builtin/lighting/[^"]+)"', line).group(1)
            # ShaderMake's lookup compares the entire key, including macro order.
            macros = re.findall(r'\{ "(\w+)", (?:"([^"]+)"|(usePushConstants\( [^)]* \))) \}', line)
            assert len(macros) == 4, line
            capture = next(value for name, value, _ in macros if name == "RT_REFLECTION_CAPTURE") == "1"
            for push in ("0", "1"):
                key = " ".join(f"{name}={value if value else push}" for name, value, _ in macros)
                for stage in ("vs", "ps"):
                    path = shader_root / f"{name}.{stage}.bin"
                    if path not in bundles:
                        bundles[path] = permutations(path)
                    assert key in bundles[path], f"Engine cannot load {path.name}: {key}"
                    lookup_count += 1
                    if stage == "ps":
                        assembly = dump(bundles[path][key])
                        targets = {int(index) for index in re.findall(r'; SV_Target\s+(\d+)\s', assembly)}
                        assert targets == ({0, 1, 2, 3} if capture else {0}), f"Wrong MRT output: {path.name}, {key}, {targets}"

        expected_resources = {
            "reflections": {"Parameters": "cb0", "ReflectionParameters": "cb1", "Scene": "t0", "Depth": "t1",
                "Positions": "t2", "Indices": "t3", "UVMaterials": "t4", "Materials": "t5", "Lights": "t6",
                "Atlas": "t7", "SurfaceRadiance": "t8", "ProbeSpecular": "t9", "SpecularResponse": "t10",
                "ReflectionNormal": "t11", "Reflection": "u0", "Stats": "u1", "Guide": "u2"},
            "reflection_filter": {"Parameters": "cb0", "ReflectionParameters": "cb1", "Raw": "t0", "Guide": "t1",
                "Previous": "t2", "PreviousGuide": "t3", "Depth": "t4", "Filtered": "u0"},
            "reflection_composite": {"Parameters": "cb0", "ReflectionParameters": "cb1", "Reflection": "t0",
                "ProbeSpecular": "t1", "Guide": "t2", "SpecularResponse": "t3", "SceneColor": "u0"},
        }
        for name, resources in expected_resources.items():
            assembly = dump((shader_root / f"rt/{name}.cs.dxil").read_bytes())
            assert "NumThreads=(8,8,1)" in assembly, f"Unexpected dispatch size: {name}"
            for constant, size in (("Parameters", 192), ("ReflectionParameters", 112)):
                assert re.search(rf'}} {constant};\s*; Offset:\s*0 Size:\s*{size}\b', assembly), f"Constant layout mismatch: {name}/{constant}"
            for resource, register in resources.items():
                assert re.search(rf'^; {resource}\s+.*\s{register}\s+1\s*$', assembly, re.MULTILINE), f"Binding mismatch: {name}/{resource}/{register}"
    print(f"PASS: {lookup_count} exact engine permutation lookups, baseline/capture MRT signatures, three compute binding layouts and constant sizes. No GPU device created.")


if __name__ == "__main__":
    main()
