"""Prove Streamline jitter agrees with the renderer's actual DX12 projection."""
import pathlib
import re
import subprocess
import tempfile


def body(source, signature):
    start = source.index('{', source.index(signature))
    depth, end = 1, start + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


root = pathlib.Path(__file__).resolve().parents[2]
projection = (root / 'neo/renderer/GLMatrix.cpp').read_text(encoding='utf-8')
taa = (root / 'neo/renderer/Passes/TemporalAntiAliasingPass.cpp').read_text(encoding='utf-8')
adapter = (root / 'neo/renderer/NeuralTemporalStreamline.cpp').read_text(encoding='utf-8')
vertex = (root / 'neo/shaders/builtin/lighting/ambient_lighting_IBL.vs.hlsl').read_text(encoding='utf-8')
backend = (root / 'neo/renderer/NVRHI/RenderBackend_NVRHI.cpp').read_text(encoding='utf-8')
assert all(f'result.position.{axis} = dot4( modelPosition, pc.rpMVPmatrix{axis.upper()} );' in vertex
           for axis in 'xyzw'), 'Scene vertices must use the submitted MVP without an implicit axis flip'
assert len(re.findall(r'result\.position\.y\s*=', vertex)) == 1, 'Unexpected scene vertex Y rewrite'
viewport = re.search(r'nvrhi::Viewport viewport\{(.+?)\};', backend, re.S).group(1)
assert re.findall(r'currentViewport\.(\w+)', viewport) == ['x1', 'x2', 'y1', 'y2'], 'DX12 must receive positive viewport height'
statement = re.search(r'constants\.jitterOffset = .+?;', adapter).group(0)
original = statement.replace('-frame.currentJitterPixels.y', 'frame.currentJitterPixels.y')
assert original != statement, 'Expected adapter conversion from projection jitter to raster jitter'
shim = r'''
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
struct idVec2 { float x,y; idVec2(float a=0,float b=0):x(a),y(b){} };
namespace sl { using float2=idVec2; }
namespace idMath { constexpr float PI=3.14159265358979323846f; }
struct { float GetFloat(){return 3.0f;} } r_znear;
struct viewDef_t {
    bool useTemporalAA=true,isObliqueProjection=false;
    int taaFrameCount=0;
    struct { bool cramZNear=false; float fov_x=100,fov_y=70; bool flipProjection=false; } renderView;
    struct { int x1=0,y1=0,x2=1279,y2=719; } viewport;
    float projectionMatrix[16]={},unjitteredProjectionMatrix[16]={};
};
void R_ObliqueProjection(viewDef_t*){throw std::runtime_error("unexpected subview");}
struct Backend { idVec2 GetCurrentPixelOffset(int frameIndex); } backEnd;
struct Frame { idVec2 currentJitterPixels; };
'''
implementation = (
    'idVec2 Backend::GetCurrentPixelOffset(int frameIndex)'
    + body(taa, 'case( int )TemporalAntiAliasingJitter::MSAA:')
    + 'void R_SetupProjectionMatrix(viewDef_t* viewDef,bool doJitter)'
    + body(projection, 'void R_SetupProjectionMatrix( viewDef_t* viewDef, bool doJitter )')
    + 'idVec2 adapterJitter(const Frame& frame){struct {idVec2 jitterOffset;} constants;'
    + statement + 'return constants.jitterOffset;}'
    + 'idVec2 originalJitter(const Frame& frame){struct {idVec2 jitterOffset;} constants;'
    + original + 'return constants.jitterOffset;}'
)
checks = r'''
idVec2 rasterPosition(const float* projection,float x,float y,float z,int width,int height){
    // GLMatrix is column-major; the frontend transposes its rows for the VS dots.
    const float clipX=projection[0]*x+projection[4]*y+projection[8]*z+projection[12];
    const float clipY=projection[1]*x+projection[5]*y+projection[9]*z+projection[13];
    const float clipW=projection[3]*x+projection[7]*y+projection[11]*z+projection[15];
    // Standard positive-height DX12 viewport conversion, +Y down.
    return {(clipX/clipW+1)*0.5f*width,(1-clipY/clipW)*0.5f*height};
}
int main(int argc,char** argv){try{
    const bool original=argc>1 && std::string(argv[1])=="--original-metadata";
    int samples=0;
    for(int scale : {1,2})for(int preset=0;preset<4;++preset)for(int frameIndex=0;frameIndex<8;++frameIndex){
        const int widths[]={1280,853,742,640},heights[]={720,480,418,360};
        const int width=widths[preset]*scale,height=heights[preset]*scale;
        viewDef_t view;view.viewport.x2=width-1;view.viewport.y2=height-1;view.taaFrameCount=frameIndex;
        R_SetupProjectionMatrix(&view,false);R_SetupProjectionMatrix(&view,true);
        Frame frame={backEnd.GetCurrentPixelOffset(frameIndex)};
        const idVec2 reported=original?originalJitter(frame):adapterJitter(frame);
        for(float z : {-8.0f,-128.0f,-2048.0f}){
            const auto base=rasterPosition(view.unjitteredProjectionMatrix,z*0.2f,z*-0.15f,z,width,height);
            const auto shifted=rasterPosition(view.projectionMatrix,z*0.2f,z*-0.15f,z,width,height);
            if(std::abs((shifted.x-base.x)-reported.x)>0.001f ||
               std::abs((shifted.y-base.y)-reported.y)>0.001f)
                throw std::runtime_error("Streamline jitter disagrees with raster displacement");
            ++samples;
        }
    }
    std::cout<<"PASS: "<<samples<<" projected points; all eight jitter offsets, native/all DLSS presets, resize and depth agree with Streamline\n";
}catch(const std::exception& error){std::cerr<<error.what();return 1;}}
'''
with tempfile.TemporaryDirectory(prefix='neuraldoom-jitter-') as directory:
    output = pathlib.Path(directory)
    cpp, exe = output / 'jitter.cpp', output / 'jitter.exe'
    cpp.write_text(shim + implementation + checks, encoding='utf-8')
    subprocess.run(['cl', '/nologo', '/EHsc', '/std:c++17', str(cpp), '/Fe:' + str(exe),
                    '/Fo:' + str(output / 'jitter.obj')], check=True, cwd=output)
    subprocess.run([str(exe)], check=True)
    wrong = subprocess.run([str(exe), '--original-metadata'], capture_output=True, text=True)
    assert wrong.returncode != 0 and 'Streamline jitter disagrees' in wrong.stderr, 'Original unconverted metadata must fail'
    print('PASS: negative control rejects the original jitter Y metadata')
