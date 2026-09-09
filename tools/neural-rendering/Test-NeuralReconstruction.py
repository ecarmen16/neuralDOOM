"""Exercise reconstruction controls and input viewport coverage without a GPU or SDK."""
import pathlib
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
adjust = menu[menu.index('void idMenuScreen_Shell_SystemOptions::idMenuDataSource_SystemSettings::AdjustField'):]
shim = r'''
#include <map>
#include <string>
#include <stdexcept>
#include <iostream>
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
struct idScreenRect { int x1=0, y1=0, x2=0, y2=0; };
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
int main(){try{
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
}catch(const std::exception&e){std::cerr<<e.what();return 1;}}
'''
with tempfile.TemporaryDirectory(prefix='neuraldoom-reconstruction-') as directory:
    root = pathlib.Path(directory)
    cpp, exe = root / 'reconstruction.cpp', root / 'reconstruction.exe'
    cpp.write_text(shim + implementation + checks, encoding='utf-8')
    subprocess.run(['cl', '/nologo', '/EHsc', '/std:c++17', str(cpp), '/Fe:' + str(exe),
                    '/Fo:' + str(root / 'reconstruction.obj')], check=True, cwd=root)
    subprocess.run([str(exe)], check=True)
