#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Round-trip actual SSR reconstruction/projection against raster pixel centers.

Run in an MSVC developer environment. Tests source-extracted engine matrix
setup and shader reconstruction with scalar/vector syntax adapters; no GPU.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def function(source, signature):
    start = source.index(signature)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
args = parser.parse_args()
backend = (args.source_root / "neo/renderer/RenderBackend.cpp").read_text(encoding="utf-8")
start = backend.index("\t\tALIGNTYPE16 const idRenderMatrix matClipToUvzw(")
end = backend.index("\n", backend.index("SetVertexParms( RENDERPARM_SHADOW_MATRIX_1_X,", start))
projection = backend[start:end]
shader = (args.source_root / "neo/shaders/builtin/legacy/bumpyenvironment2.ps.hlsl").read_text(encoding="utf-8")
reconstruct = function(shader, "float3 ReconstructPositionCS(")
# Adapt HLSL vector properties and texture access without changing arithmetic.
reconstruct = reconstruct.replace("texelFetch( t_Depth, hitPixel, 0 ).r", "sampleDepth( hitPixel )")
reconstruct = reconstruct.replace("pc.rpWindowCoord.xy", "float2( pc.rpWindowCoord.x, pc.rpWindowCoord.y )")
reconstruct = reconstruct.replace("csP.xyz /= csP.w;", "csP = csP / csP.w;")
reconstruct = reconstruct.replace("return csP.xyz;", "return float3( csP.x, csP.y, csP.z );")
shim = r'''
#include <cmath>
#include <cstring>
#include <iostream>
#include <stdexcept>
#define ALIGNTYPE16
struct int2 { int x,y; };
struct float2 {
    float x,y;
    float2(float a,float b):x(a),y(b){}
    float2(int2 p):x(float(p.x)),y(float(p.y)){}
    float2 operator+(float s)const{return {x+s,y+s};}
    float2 operator*(float2 s)const{return {x*s.x,y*s.y};}
};
float2 operator*(int2 p,float2 scale){return float2(p)*scale;}
struct float3 {
    float x,y,z;
    float3(float a,float b,float c):x(a),y(b),z(c){}
    float3 operator*(float s)const{return {x*s,y*s,z*s};}
};
struct float4 {
    float x=0,y=0,z=0,w=0;
    float4()=default;
    float4(float a,float b,float c,float d):x(a),y(b),z(c),w(d){}
    float4(float3 v,float s):x(v.x),y(v.y),z(v.z),w(s){}
    float4 operator/(float s)const{return {x/s,y/s,z/s,w/s};}
};
float dot4(float4 a,float4 b){return a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w;}
struct idRenderMatrix {
    float a[4][4]={};
    idRenderMatrix()=default;
    idRenderMatrix(float a0,float a1,float a2,float a3,float b0,float b1,float b2,float b3,
                   float c0,float c1,float c2,float c3,float d0,float d1,float d2,float d3)
        :a{{a0,a1,a2,a3},{b0,b1,b2,b3},{c0,c1,c2,c3},{d0,d1,d2,d3}}{}
    float* operator[](int i){return a[i];}
    const float* operator[](int i)const{return a[i];}
    static void Multiply(const idRenderMatrix& x,const idRenderMatrix& y,idRenderMatrix& result){
        for(int i=0;i<4;++i)for(int j=0;j<4;++j){result.a[i][j]=0;for(int k=0;k<4;++k)result.a[i][j]+=x.a[i][k]*y.a[k][j];}
    }
};
struct Viewport { int width,height; int GetWidth()const{return width;} int GetHeight()const{return height;} };
struct View {Viewport viewport;idRenderMatrix projectionRenderMatrix;} view;
View* viewDef=&view;
struct Output {int width,height;int GetWidth()const{return width;}int GetHeight()const{return height;}} output;
Output* renderSystem=&output;
struct Parameters {float4 rpWindowCoord,rpProjectionMatrixZ,rpShadowMatrices[8];} pc;
constexpr int RENDERPARM_SHADOW_MATRIX_1_X=0;
void SetVertexParms(int,const float* matrix,int){std::memcpy(pc.rpShadowMatrices+4,matrix,16*sizeof(float));}
int2 expectedPixel;
float deviceDepth;
float sampleDepth(int2 pixel){
    if(pixel.x!=expectedPixel.x || pixel.y!=expectedPixel.y)throw std::runtime_error("SSR sampled a different depth texel");
    return deviceDepth;
}
void setup(){
'''
checks = r'''
int main(){try{
    int cases=0;
    const float offsets[][2]={{0,0},{.0625f,-.1875f},{-.4375f,.0625f},{.4375f,-.4375f},{-.25f,.35f}};
    for(auto display : {int2{2560,720},int2{1920,1080}}){
        output.width=display.x;output.height=display.y;
        for(float scale : {1.f,2.f/3.f,.58f,.5f}){
            const int width=int(std::ceil(display.x*scale)),height=int(std::ceil(display.y*scale));
            view.viewport={width,height};pc.rpWindowCoord={1.f/width,1.f/height,float(width),float(height)};
            for(const auto& jitter:offsets){
                const float sx=1.3f,sy=1.7f,jx=-2*jitter[0]/width,jy=-2*jitter[1]/height,nearZ=3.f;
                view.projectionRenderMatrix={sx,0,jx,0, 0,sy,jy,0, 0,0,-.999f,-nearZ, 0,0,-1,0};
                pc.rpProjectionMatrixZ={0,0,-.999f,-nearZ};
                // Exact inverse of the standard jittered infinite-far projection.
                pc.rpShadowMatrices[0]={1/sx,0,0,jx/sx};pc.rpShadowMatrices[1]={0,1/sy,0,jy/sy};
                pc.rpShadowMatrices[2]={0,0,0,-1};pc.rpShadowMatrices[3]={0,0,-1/nearZ,.999f/nearZ};
                setup();
                for(int2 pixel:{int2{0,0},int2{width/2,height/2},int2{width-1,height-1}}){
                    expectedPixel=pixel;
                    for(float distance : {4.5f,512.f}){
                        deviceDepth=.999f-nearZ/distance;
                        float3 camera=ReconstructPositionCS(pixel);
                        float4 point(camera,1);
                        float clipW=dot4(point,pc.rpShadowMatrices[7]);
                        float x=dot4(point,pc.rpShadowMatrices[4])/clipW;
                        float y=dot4(point,pc.rpShadowMatrices[5])/clipW;
                        if(std::abs(x-(pixel.x+.5f))>.002f || std::abs(y-(pixel.y+.5f))>.002f){
                            std::cerr<<"output="<<display.x<<"x"<<display.y<<" input="<<width<<"x"<<height
                                     <<" pixel="<<pixel.x<<","<<pixel.y<<" reprojected="<<x<<","<<y<<"\n";
                            throw std::runtime_error("SSR projection must return the sampled input pixel center");
                        }
                        ++cases;
                    }
                }
            }
        }
    }
    std::cout<<"PASS: "<<cases<<" SSR depth-center round trips across native/Quality/Balanced/Performance extents, camera jitter, corners and depth\n";
}catch(const std::exception& error){std::cerr<<error.what()<<"\n";return 1;}}
'''
with tempfile.TemporaryDirectory(prefix="neuraldoom-ssr-") as directory:
    root = Path(directory)
    source, executable = root / "ssr.cpp", root / "ssr.exe"
    source.write_text(shim + projection + "\n}\n" + reconstruct + checks, encoding="utf-8")
    subprocess.run(["cl", "/nologo", "/EHsc", "/std:c++17", str(source), "/Fe:" + str(executable),
                    "/Fo:" + str(root / "ssr.obj")], check=True, cwd=root)
    subprocess.run([str(executable)], check=True)
