"""Exercise reconstruction controls and input viewport coverage without a GPU or SDK."""
import pathlib
import re
import subprocess
import tempfile


def body(source, signature):
    start = source.index('{', source.index(signature))
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


temporal = pathlib.Path('neo/renderer/NeuralTemporal.cpp').read_text(encoding='utf-8')
controls = pathlib.Path('neo/renderer/RayTracingDiagnostic.cpp').read_text(encoding='utf-8')
menu = pathlib.Path('neo/d3xp/menus/MenuScreen_Shell_SystemOptions.cpp').read_text(encoding='utf-8')
world = pathlib.Path('neo/renderer/RenderWorld.cpp').read_text(encoding='utf-8')
render_system = pathlib.Path('neo/renderer/RenderSystem.cpp').read_text(encoding='utf-8')
backend = pathlib.Path('neo/renderer/RenderBackend.cpp').read_text(encoding='utf-8')
source_box_start = backend.index('idVec4 currentRenderSourceBox(')
source_box_initializer = backend[source_box_start:backend.index(';', source_box_start) + 1]
source_box_condition = 'if( _viewDef->neuralBackendMode == 3 )'
source_box_block = source_box_initializer + source_box_condition + body(backend[source_box_start:], source_box_condition)
draw_view = body(backend, 'void idRenderBackend::DrawViewInternal(')
assert draw_view.count('blitParms.sourceBox = currentRenderSourceBox;') == 2, 'Both screen snapshots must use the active input region'
ao_blocks = []
for name in ('ambient_lighting_IBL', 'ambient_lightgrid_IBL'):
    shader = pathlib.Path(f'neo/shaders/builtin/lighting/{name}.ps.hlsl').read_text(encoding='utf-8')
    start = shader.index('uint aoWidth, aoHeight;')
    end = shader.index(';', shader.index('float2 screenTexCoord =', start)) + 1
    ao_blocks.append(shader[start:end])
    assert 't_Ssao.Sample( s_LinearClamp, screenTexCoord )' in shader, 'Retain filtered/clamped white AO fallback'
ssr = pathlib.Path('neo/shaders/builtin/legacy/bumpyenvironment2.ps.hlsl').read_text(encoding='utf-8')
ssr_pixel = re.search(r'texelFetch\( t_ScreenNormals, (.+?), 0 \)\.rgb', ssr).group(1)
adjust = menu[menu.index('void idMenuScreen_Shell_SystemOptions::idMenuDataSource_SystemSettings::AdjustField'):]
shim = r'''
#include <map>
#include <string>
#include <stdexcept>
#include <iostream>
#include <cmath>
enum { ANTI_ALIASING_TAA = 2, CMD_EXEC_APPEND = 1 };
struct CVar { int value=1; int GetInteger(){return value;} void SetInteger(int v){value=v;} };
CVar r_neuralReconstructionMode, r_neuralNRReconstructionMode;
struct CVars {
    std::map<std::string,int> values;
    bool GetCVarBool(const char* n){return values[n]!=0;}
    int GetCVarInteger(const char* n){return values[n];}
    void SetCVarBool(const char* n,bool v){values[n]=v;}
    void SetCVarInteger(const char* n,int v){values[n]=v;}
} vars;
CVars* cvarSystem=&vars;
struct Commands {
    int resets=0;
    void BufferCommandText(int, const char* text){
        if(std::string(text)!="neuralHistoryReset\n") throw std::runtime_error("unexpected command");
        ++resets;
    }
} commands;
Commands* cmdSystem=&commands;
struct Common {
    void Printf(const char*, ...){}
    void Error(const char*){throw std::runtime_error("invalid crop");}
} commonInstance;
Common* common=&commonInstance;
bool sdk=true;
bool R_StreamlineIsDLSSSupported(){return sdk;}
struct idScreenRect {
    int x1=0, y1=0, x2=0, y2=0;
    int GetWidth()const{return x2-x1+1;} int GetHeight()const{return y2-y1+1;}
};
struct idVec4 {
    float x,y,z,w;
    idVec4(float a,float b,float c,float d):x(a),y(b),z(c),w(d){}
    void Set(float a,float b,float c,float d){x=a;y=b;z=c;w=d;}
};
namespace nvrhi { struct TextureDesc { unsigned width=1280,height=720; }; }
struct Texture {
    nvrhi::TextureDesc desc;
    const nvrhi::TextureDesc& getDesc(){return desc;}
    void GetDimensions(unsigned& width,unsigned& height){width=desc.width;height=desc.height;}
} hdrTexture, t_Ssao;
struct Image { Texture* GetTextureHandle(){return &hdrTexture;} } hdrImage;
struct Images { Image* currentRenderHDRImage=&hdrImage; } images;
Images* globalImages=&images;
using uint=unsigned;
struct float2 { float x,y; float2(float a,float b):x(a),y(b){} };
float2 operator/(float2 a,float2 b){return {a.x/b.x,a.y/b.y};}
struct int2 { int x,y; explicit int2(float2 p):x(int(p.x)),y(int(p.y)){} };
struct Fragment { struct { float2 xy; } position; };
struct Gui { void EmitFullScreen(){} void Clear(){} } gui;
class idRenderSystemLocal {
public:
    idScreenRect renderCrops[2];
    int currentRenderCrop=0, width=1280, height=720;
    Gui* guiModel=&gui;
    bool IsInitialized(){return true;}
    int GetWidth(){return width;}
    int GetHeight(){return height;}
    void PerformResolutionScaling(int&, int&){}
    void GetCroppedViewport(idScreenRect* viewport){*viewport=renderCrops[currentRenderCrop];}
    void CropRenderSize(int width, int height);
    void CropRenderSize(int x, int y, int width, int height, bool topLeftAncor);
} tr;
CVar r_screenFraction;
struct View { int neuralBackendMode, neuralDLSSQuality; idScreenRect viewport; };
int requestedWidth=853, requestedHeight=480;
bool R_StreamlineDLSSRenderSize(int, int, int& width, int& height, int){
    if(!sdk)return false;
    width=requestedWidth; height=requestedHeight; return true;
}
'''
implementation = (
    'int R_NeuralReconstructionMode()' + body(temporal, 'int R_NeuralReconstructionMode()') + '\n'
    'bool R_SetNeuralReconstructionMode(int mode)' + body(temporal, 'bool R_SetNeuralReconstructionMode(') + '\n'
    'void toggle()' + body(controls, 'CONSOLE_COMMAND_SHIP( neuralReconstructionToggle,') + '\n'
    'void adjust(int adjustAmount)' + body(adjust, 'if( fieldIndex == SYSTEM_FIELD_RECONSTRUCTION )') + '\n'
    'void idRenderSystemLocal::CropRenderSize(int width, int height)'
    + body(render_system, 'void idRenderSystemLocal::CropRenderSize( int width, int height )') + '\n'
    'void idRenderSystemLocal::CropRenderSize(int x, int y, int width, int height, bool topLeftAncor)'
    + body(render_system, 'void idRenderSystemLocal::CropRenderSize( int x, int y, int width, int height, bool topLeftAncor )') + '\n'
    'void cropView(View* parms){int windowWidth=tr.GetWidth(), windowHeight=tr.GetHeight();'
    + body(world, 'else\n\t{\n\t\t// Explicit DLSS presets own the input extent') + '}\n'
    'idVec4 screenSourceBox(View* _viewDef){' + source_box_block + 'return currentRenderSourceBox;}\n'
    'idVec4 originalFullscreenBox(View*){' + source_box_initializer + 'return currentRenderSourceBox;}\n'
    + ''.join(f'float2 aoCoordinates{index}(Fragment fragment){{{block}return screenTexCoord;}}\n'
              for index, block in enumerate(ao_blocks))
    + 'int2 ssrNormalPixel(Fragment fragment){return ' + ssr_pixel + ';}\n'
)
checks = r'''
void require(bool ok){if(!ok)throw std::runtime_error("reconstruction regression");}
void checkViewport(){
    // The SDK tags [0, renderWidth) x [0, renderHeight). Every tagged pixel
    // must belong to the raster viewport, including reduced input and resize.
    for(int scale : {1,2})for(int nr : {0,1})for(bool available : {false,true}){
        tr.width=1280*scale;tr.height=720*scale;
        vars.values["r_neuralCompatibilityEnable"]=nr;sdk=available;
        const int widths[]={853,742,640}, heights[]={480,418,360};
        for(int quality=0;quality<3;++quality){
            requestedWidth=widths[quality]*scale;requestedHeight=heights[quality]*scale;
            tr.currentRenderCrop=0;tr.renderCrops[0]={0,0,tr.width-1,tr.height-1};
            r_screenFraction.value=50; // DLSS must own its input extent.
            View view={3,quality,{}};cropView(&view);
            const int width=available?requestedWidth:tr.width, height=available?requestedHeight:tr.height;
            require(view.viewport.x1==0 && view.viewport.y1==0);
            require(view.viewport.x2==width-1 && view.viewport.y2==height-1);
        }
        // Native/DLAA behavior must preserve the previous crop policy.
        for(int backend : {0,1,2}){
            tr.currentRenderCrop=0;tr.renderCrops[0]={0,0,tr.width-1,tr.height-1};
            View view={backend,0,{}};cropView(&view);
            const bool scaled=backend!=2 && !nr;
            require(view.viewport.x1==0 && view.viewport.y1==(scaled?tr.height/2:0));
            require(view.viewport.x2==(scaled?tr.width/2:tr.width)-1 && view.viewport.y2==tr.height-1);
        }
    }
    sdk=true;
    std::cout<<"PASS: DLSS tagged input coverage for all presets, resize and SDK fallback; legacy crop preserved\n";
}
void checkScreenCoordinates(bool originalFullscreen=false){
    // Exercise the actual extracted snapshot and shader expressions, then
    // identify the raster texel reached by arbitrary view-relative samples.
    // This catches stretching a reduced viewport over unrelated allocation pixels.
    for(int scale : {1,2}){
        tr.width=1280*scale;tr.height=720*scale;
        hdrTexture.desc={unsigned(tr.width),unsigned(tr.height)};
        t_Ssao.desc=hdrTexture.desc;
        const int widths[]={1280,853,742,640}, heights[]={720,480,418,360};
        for(int preset=0;preset<4;++preset)for(int offset : {0,1}){
            const int width=widths[preset]*scale-(offset?32:0);
            const int height=heights[preset]*scale-(offset?32:0);
            const int x=offset?11:0,y=offset?19:0;
            View view={preset?3:2,preset-1,{x,y,x+width-1,y+height-1}};
            idVec4 box=originalFullscreen?originalFullscreenBox(&view):screenSourceBox(&view);
            if(!preset){
                require(box.x==0 && box.y==0 && box.z==1 && box.w==1);
            }
            for(float u : {0.5f/width,0.37f,(width-0.5f)/width})
            for(float v : {0.5f/height,0.61f,(height-0.5f)/height}){
                Fragment fragment={{{x+u*width,y+v*height}}};
                if(preset){
                    const float sourceX=(box.x+u*box.z)*tr.width;
                    const float sourceY=(box.y+v*box.w)*tr.height;
                    if(std::abs(sourceX-fragment.position.xy.x)>0.001f ||
                       std::abs(sourceY-fragment.position.xy.y)>0.001f)
                        throw std::runtime_error("screen snapshot coordinate regression");
                    require(sourceX>=x && sourceX<x+width && sourceY>=y && sourceY<y+height);
                }
                for(auto coordinates : {aoCoordinates0(fragment),aoCoordinates1(fragment)}){
                    require(std::abs(coordinates.x*tr.width-fragment.position.xy.x)<0.001f);
                    require(std::abs(coordinates.y*tr.height-fragment.position.xy.y)<0.001f);
                }
                const int2 normal=ssrNormalPixel(fragment);
                require(normal.x==int(fragment.position.xy.x) && normal.y==int(fragment.position.xy.y));
            }
        }
        for(int backend : {0,1,2}){
            View view={backend,0,{11,19,319,239}};
            const auto box=screenSourceBox(&view);
            require(box.x==0 && box.y==0 && box.z==1 && box.w==1);
        }
    }
    std::cout<<"PASS: screen snapshot, AO and SSR raster coordinates for native, all DLSS presets, offsets and resize; other backends unchanged\n";
}
int main(int argc,char** argv){try{
if(argc>1 && std::string(argv[1])=="--original-fullscreen-source"){
    checkScreenCoordinates(true);return 0;
}
require(R_NeuralReconstructionMode()==1);
for(int nr=0;nr<=1;++nr){
    vars.values["r_neuralCompatibilityEnable"]=nr;
    for(int mode=nr;mode<=4;++mode){
        const int other=nr?r_neuralReconstructionMode.value:r_neuralNRReconstructionMode.value;
        const int resets=commands.resets;
        require(R_SetNeuralReconstructionMode(mode));
        require(R_NeuralReconstructionMode()==mode && commands.resets==resets+1);
        require((nr?r_neuralReconstructionMode.value:r_neuralNRReconstructionMode.value)==other);
        require(vars.values["r_neuralBackend"]==(mode==0?0:mode==1?2:3));
        require(vars.values["r_neuralDLSSQuality"]==(mode>=2?mode-2:0));
        require(vars.values["r_useTemporalAA"]==1 && vars.values["r_antiAliasing"]==ANTI_ALIASING_TAA);
        adjust(1);require(R_NeuralReconstructionMode()==(mode==4?nr:mode+1));
        adjust(-1);require(R_NeuralReconstructionMode()==mode);
        toggle();require(R_NeuralReconstructionMode()==(nr?(mode==4?1:mode+1):(mode==1?0:1)));
    }
    for(int bad : {-1,5,100}){
        const auto saved=vars.values;const int resets=commands.resets, mode=R_NeuralReconstructionMode();
        require(!R_SetNeuralReconstructionMode(bad));
        require(saved==vars.values && resets==commands.resets && mode==R_NeuralReconstructionMode());
    }
    sdk=false;
    const auto saved=vars.values;const int resets=commands.resets, mode=R_NeuralReconstructionMode();
    require(!R_SetNeuralReconstructionMode(2));adjust(1);toggle();
    require(saved==vars.values && resets==commands.resets && mode==R_NeuralReconstructionMode());
    sdk=true;
}
require(!R_SetNeuralReconstructionMode(0)); // NR must not silently bypass its evaluation trigger.
std::cout<<"PASS: independent preferences, mode mapping, history reset, menu/key cycling and unavailable-SDK no-op\n";
checkViewport();
checkScreenCoordinates();
}catch(const std::exception&e){std::cerr<<e.what();return 1;}}
'''
with tempfile.TemporaryDirectory(prefix='neuraldoom-reconstruction-') as directory:
    root = pathlib.Path(directory)
    cpp, exe = root / 'reconstruction.cpp', root / 'reconstruction.exe'
    cpp.write_text(shim + implementation + checks, encoding='utf-8')
    subprocess.run(['cl', '/nologo', '/EHsc', '/std:c++17', str(cpp), '/Fe:' + str(exe),
                    '/Fo:' + str(root / 'reconstruction.obj')], check=True, cwd=root)
    subprocess.run([str(exe)], check=True)
    original = subprocess.run([str(exe), '--original-fullscreen-source'], capture_output=True, text=True)
    assert original.returncode != 0 and 'screen snapshot coordinate regression' in original.stderr, 'Original full-allocation snapshot must fail'
    print('PASS: negative control rejects the original fullscreen source region')
