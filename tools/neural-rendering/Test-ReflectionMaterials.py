#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise real stage preparation and secondary reflection shading without a GPU.

Requires DXC and, for material cases, an MSVC developer environment. Scalar color
fixtures execute production fragments; full shader compilation separately catches
undefined floating-point dataflow and verifies shared material/constant layouts.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def function_body(source, signature):
    begin = source.index('{', source.index(signature))
    depth = 1
    end = begin + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin + 1:end - 1]


def compiled_contract(root, dxc, directory):
    for name in ('reflections', 'diffuse_bounce'):
        binary, assembly = directory / (name + '.dxil'), directory / (name + '.asm')
        subprocess.run([str(dxc), '-T', 'cs_6_5', '-E', 'main',
                        str(root / f'neo/shaders/rt/{name}.cs.hlsl'),
                        '-Fo', str(binary), '-Fc', str(assembly)], check=True)
        text = assembly.read_text()
        # Unused texture coordinates and resource metadata legitimately use undef;
        # incoming floating-point phi/select operands must be defined instead.
        undefined = [line.strip() for line in text.splitlines()
                     if re.search(r'\b(?:phi|select)\b.*\bundef\b', line)]
        assert not undefined, f'{name}: undefined shader values enter control-flow joins: {undefined}'
        assert re.search(r'} Parameters;\s*; Offset:\s*0 Size:\s*192\b', text), name
        material_layout = text.split('; Resource bind info for Materials\n', 1)[1].split('; Resource bind info for ', 1)[0]
        assert re.search(r'} \$Element;\s*; Offset:\s*0 Size:\s*96\b', material_layout), name
        for offset, member in enumerate(('diffuse', 'emissive', 'diffuseS', 'diffuseT', 'emissiveS', 'emissiveT')):
            assert re.search(rf'float4 {member};\s*; Offset:\s*{offset * 16}\b', material_layout), (name, member)
    print('PASS: reflection/GI DXIL has defined control-flow values and unchanged 192/96-byte layouts')


def material_cases(root, directory):
    renderer = (root / 'neo/renderer/RayTracingDiagnostic.cpp').read_text()
    stage = function_body(renderer, 'void PrepareStage(')
    materials = (root / 'neo/shaders/rt/ray_materials.hlsli').read_text()
    surface = function_body(materials, 'bool Surface(')
    # Keep the actual texture evaluation and validity decision; geometric ray
    # intersection is supplied by fixtures, since no GPU device is created.
    surface = surface[surface.index('Material m ='):]
    reflection = (root / 'neo/shaders/rt/reflections.cs.hlsl').read_text()
    shade = reflection[reflection.index('        float3 hitNormal, hitAlbedo, emission;'):]
    shade = shade[:shade.index('        if (sampled)\n')]
    composite = (root / 'neo/shaders/rt/reflection_composite.cs.hlsl').read_text()
    delta = re.search(r'float3 delta = ([^;]+);', composite).group(1)
    delta = delta.replace('reflection.rgb', 'result.radiance').replace('reflection.a', 'result.coverage')
    delta = delta.replace('ProbeSpecular[pixel].rgb', 'probe')
    # HLSL scalar channel translation: each case uses equal RGB channels. Keep
    # branch/coverage code verbatim; replace only vector spelling and qualifiers.
    surface = surface.replace('float3(', 'Coordinates(').replace('float4(uv, 0, 1)', 'idVec4(uv, uv, 0, 1)')
    for name in ('r', 'g', 'b'):
        shade = shade.replace('radiance.' + name, 'radiance')
    for text_name in ('surface', 'shade'):
        value = surface if text_name == 'surface' else shade
        value = value.replace('float3 ', 'float ').replace('float4 ', 'idVec4 ')
        value = re.sub(r'\b(?:all|any)\(', 'identity(', value)
        value = value.replace('AtlasOptions.y', 'debug')
        if text_name == 'surface':
            surface = value
        else:
            shade = value
    program = r'''
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
using uint32 = unsigned int;
using uint = unsigned int;
using std::isfinite;
float max(float a,float b) { return std::max(a,b); }
float min(float a,float b) { return std::min(a,b); }
float saturate(float v) { return std::clamp(v, 0.f, 1.f); }
bool identity(bool v) { return v; }
float lerp(float a, float b, float w) { return a * (1 - w) + b * w; }
struct idVec4 {
    float x, y, z, w;
    idVec4(float a=0, float b=0, float c=0, float d=0): x(a), y(b), z(c), w(d) {}
    float& operator[](int c) { return (&x)[c]; }
};
float dot(idVec4 a, idVec4 b) { return a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w; }
namespace nvrhi { struct ICommandList {}; }
namespace idMath { float ClampFloat(float a,float b,float v) { return std::clamp(v,a,b); } }
struct Texture { bool hasMatrix=false; int image=1; float matrix[16]={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}; };
struct shaderStage_t { int conditionRegister=0; Texture texture; struct { int registers[3]={1,2,3}; } color; };
bool textureAvailable=true;
bool CacheTexture(nvrhi::ICommandList*,int,uint32,int) { return textureAvailable; }
void RB_GetShaderTextureMatrix(const float*,const Texture* texture,float* matrix) {
    std::copy(texture->matrix,texture->matrix+16,matrix);
}
void PrepareStage(nvrhi::ICommandList* list,const shaderStage_t* stage,const float* regs,uint32 slice,int decode,idVec4& tint,idVec4& s,idVec4& t) {
''' + stage + r'''
}
struct Material { idVec4 diffuse,emissive,diffuseS,diffuseT,emissiveS,emissiveT; };
Material Materials[1];
struct Coordinates { float u,v,slice; Coordinates(float a,float b,float c):u(a),v(b),slice(c){} };
struct AtlasType {
    struct Color { float rgb; };
    float texel[2]={1,1}, lastU[2]={}, lastV[2]={};
    Color SampleLevel(int,Coordinates c,int) {
        int slice=int(c.slice); lastU[slice]=c.u; lastV[slice]=c.v;
        return {texel[slice]};
    }
} Atlas;
int LinearWrap=0, debug=0;
float uv=0.25f; idVec4 a;
bool Surface(uint32,float,float,float& normal,float& albedo,float& emission,bool& supportedMaterial) {
    normal=1; supportedMaterial=true; // Existing Surface accepts any finite result.
''' + surface.replace('m.diffuse.rgb', 'm.diffuse.x').replace('m.emissive.rgb', 'm.emissive.x') + r'''
}
bool Surface(uint32 p,float b,float d,float& n,float& a,float& e) {
    bool ignored; return Surface(p,b,d,n,a,e,ignored);
}
float cacheAvailability=0, cacheValue=4;
float CachedRadiance(float,float& cached) { cached=cacheValue; return cacheAvailability; }
float Incident(float,float) { return 2; }
struct Ray { float Origin=0; } ray;
struct Reflected { float CommittedRayT() { return 2; } float CommittedTriangleBarycentrics() { return 0.2f; } } reflected;
int Stats[8]={}; void InterlockedAdd(int& v,int amount) { v+=amount; }
struct Result { float radiance,coverage; };
Result shade_hit(bool dynamicHit) {
    float direction=1, weight=1, sum=0, hitWeight=0; uint32 hitPrimitive=0;
    // 'continue' in the production block targets the ray-sample loop.
    for (int sample=0;sample<1;++sample) {
''' + shade + r'''
    }
    return {sum,hitWeight};
}
float probe_delta(Result result) {
    const float probe=8;
    return ''' + delta + r''';
}
void require(bool value,const char* message) { if (!value) { std::cerr<<message<<"\n"; std::exit(1); } }
int main() {
    shaderStage_t stage; float regs[4]={1,0,0,0};
    Material& m=Materials[0];
    auto prepare=[&](bool diffuse,bool emissive) {
        PrepareStage(nullptr,diffuse?&stage:nullptr,regs,0,1,m.diffuse,m.diffuseS,m.diffuseT);
        PrepareStage(nullptr,emissive?&stage:nullptr,regs,1,2,m.emissive,m.emissiveS,m.emissiveT);
    };
    auto check=[&](bool dynamic,float cache,float expectedRadiance,float expectedCoverage,const char* label) {
        cacheAvailability=cache; Result result=shade_hit(dynamic);
        require(std::abs(result.coverage-expectedCoverage)<1e-6,label);
        require(std::abs(result.radiance-expectedRadiance)<1e-6,label);
    };
    prepare(false,false);
    check(false,0,0,0,"unsupported uncached hit must retain probes");
    check(false,0.5f,0,0,"unsupported partial cache must retain probes");
    check(false,0.998f,0,0,"unsupported near-complete cache still needs authored fallback");
    require(probe_delta(shade_hit(false))==0,"unsupported fallback must not subtract native probes");
    check(false,0.999f,4,1,"complete native cache threshold can replace probes");
    check(false,1,4,1,"unsupported material with native cache must use native radiance");
    check(true,1,0,0,"dynamic unsupported hit must retain probes rather than use stale cache");
    prepare(true,false);
    check(false,0,0,1,"authored black diffuse is a valid reflection, not missing material");
    require(probe_delta(shade_hit(false))==-8,"valid black reflection must replace matching native probes");
    check(true,1,0,1,"dynamic authored black must bypass native cache");
    regs[1]=regs[2]=regs[3]=3;
    prepare(false,true);
    check(false,0,3,1,"emissive-only material must remain valid");
    check(false,0.5f,5,1,"emissive partial cache counts emission once");
    check(true,1,3,1,"dynamic emissive uses authored radiance");
    debug=3; check(false,1,4,1,"late diagnostic native cache must not duplicate emission"); debug=0;
    prepare(true,false);
    check(false,0,2,1,"authored diffuse uncached uses incident lighting");
    check(false,0.5f,3,1,"authored diffuse partial cache blends radiance");
    check(true,1,2,1,"dynamic diffuse uses incident lighting, never the static cache");
    Atlas.texel[0]=0;
    check(false,0,0,1,"black diffuse texture remains supported despite zero brightness");
    Atlas.texel[0]=1;
    regs[0]=0; prepare(true,true);
    check(false,0,0,0,"disabled stages must retain probes");
    regs[0]=1; textureAvailable=false; prepare(true,true);
    check(false,0,0,0,"unavailable textures must retain probes");
    textureAvailable=true; stage.texture.hasMatrix=true;
    stage.texture.matrix[0]=2; stage.texture.matrix[5]=3;
    stage.texture.matrix[12]=0.1f; stage.texture.matrix[13]=0.2f;
    prepare(true,false);
    float albedo,emission,normal; bool supported;
    require(Surface(0,0,1,normal,albedo,emission,supported)&&supported,"matrix stage retains validity");
    require(std::abs(Atlas.lastU[0]-0.6f)<1e-6 && std::abs(Atlas.lastV[0]-0.95f)<1e-6,
        "validity/shadow fields must not alter texture coordinates");
    std::cout<<"PASS: actual stage/shader fragments preserve probes for unavailable materials and support black/emissive/dynamic/cache/matrix cases\n";
}
'''
    source, executable = directory / 'materials.cpp', directory / 'materials.exe'
    source.write_text(program)
    subprocess.run(['cl', '/nologo', '/std:c++17', '/EHsc', str(source), '/Fe:' + str(executable)], cwd=directory, check=True)
    subprocess.run([str(executable)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--dxc', type=Path, required=True)
    parser.add_argument('--check', choices=('all','compiled','materials'), default='all')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='neuraldoom-reflection-materials-') as temporary:
        directory = Path(temporary)
        if args.check in ('all','compiled'):
            compiled_contract(args.source_root,args.dxc,directory)
        if args.check in ('all','materials'):
            material_cases(args.source_root,directory)


if __name__ == '__main__':
    main()
