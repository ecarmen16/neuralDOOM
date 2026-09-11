"""Execute the source relaunch filter with quoted command-line/CVar CPU fixtures.

The small tokenizer models the engine's keepAsStrings, no-escape path. This is
an offline argument regression; it never starts or restarts the game.
"""
import pathlib
import subprocess
import tempfile


def body(source, signature):
    start = source.index('{', source.index(signature))
    end, depth = start + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'neo/sys/win32/win_main.cpp').read_text(encoding='utf-8')
profile = (root / 'neo/framework/PlayerProfile.cpp').read_text(encoding='utf-8')
assert 'Sys_SettingsRelaunchCommandLine( Sys_GetCmdLine() )' in body(source, 'void Sys_ReLaunch()')
args_source = (root / 'neo/idlib/CmdArgs.cpp').read_text(encoding='utf-8')
assert 'LEXFL_NOSTRINGESCAPECHARS' in body(args_source, 'void idCmdArgs::TokenizeString')
assert 'keepAsStrings ? LEXFL_ONLYSTRINGS : 0' in args_source

shim = r'''
#include <string>
#include <vector>
#include <map>
#include <cstring>
#include <cctype>
#include <cstdarg>
#include <cstdio>
#include <stdexcept>
#include <iostream>
#define ARRAY_COUNT(a) (sizeof(a)/sizeof((a)[0]))
enum {CVAR_STATIC=1,CVAR_ARCHIVE=2,CVAR_INIT=4,CVAR_ROM=8,CVAR_SERVERINFO=16,CVAR_NETWORKSYNC=32};
struct idStr:std::string {using std::string::string;idStr(const std::string&s):std::string(s){}void Append(const char*s){append(s);}static int Icmp(const char*a,const char*b){return _stricmp(a,b);}};
const char*va(const char*fmt,...){static char buffer[128];va_list a;va_start(a,fmt);vsnprintf(buffer,sizeof(buffer),fmt,a);va_end(a);return buffer;}
struct idCmdArgs {
 std::vector<std::string>args;
 idCmdArgs(const char*s,bool strings){if(!strings)throw std::runtime_error("wrong engine tokenizer mode");
  while(*s){while(*s&&isspace((unsigned char)*s))++s;if(!*s)break;
   std::string token;if(*s=='"'||*s=='\''){const char quote=*s++;while(*s&&*s!=quote)token+=*s++;if(*s)++s;}
   else{while(*s&&!isspace((unsigned char)*s))token+=*s++;}args.push_back(token);}}
 int Argc()const{return int(args.size());}const char*Argv(int i)const{return i>=0&&i<Argc()?args[i].c_str():"";}
};
struct idCVar {std::string name,value;int flags;int GetFlags()const{return flags;}const char*GetName()const{return name.c_str();}};
struct CVars {std::map<std::string,idCVar>vars;idCVar*Find(const char*k){auto i=vars.find(k);return i==vars.end()?nullptr:&i->second;}int GetCVarInteger(const char*k){auto v=Find(k);return v?stoi(v->value):0;}void add(const char*k,const char*v,int flags=CVAR_STATIC|CVAR_ARCHIVE){vars[k]={k,v,flags};}} cvars;
CVars*cvarSystem=&cvars;
struct idPlayerProfile{static bool IsResettablePreference(const idCVar*);};
void require(bool pass,const char*why){if(!pass)throw std::runtime_error(why);}
std::string setting(const idCmdArgs&a,const char*key){for(int i=0;i+2<a.Argc();i++)if(idStr::Icmp(a.Argv(i),"+set")==0&&idStr::Icmp(a.Argv(i+1),key)==0)return a.Argv(i+2);return "absent";}
'''
implementation = (
    'bool idPlayerProfile::IsResettablePreference(const idCVar* cvar)'
    + body(profile, 'bool idPlayerProfile::IsResettablePreference')
    + 'idStr Sys_SettingsRelaunchCommandLine(const char* original)'
    + body(source, 'static idStr Sys_SettingsRelaunchCommandLine')
)
checks = r'''
int main(int argc,char**){try{
 cvars.add("fs_basepath","",CVAR_STATIC|CVAR_INIT);cvars.add("fs_savepath","",CVAR_STATIC|CVAR_INIT);
 cvars.add("r_streamlineEnable","1",CVAR_STATIC|CVAR_INIT);cvars.add("r_neuralCompatibilityEnable","1",CVAR_STATIC|CVAR_INIT|CVAR_ARCHIVE);
 cvars.add("r_graphicsAPI","dx12",CVAR_STATIC|CVAR_INIT|CVAR_ARCHIVE);cvars.add("r_neuralBackend","2",CVAR_STATIC);
 cvars.add("sys_neuralLauncherSession","1",CVAR_STATIC|CVAR_INIT);
 cvars.add("r_fullscreen","0");cvars.add("r_windowWidth","1280");cvars.add("r_hdrOutput","0");cvars.add("r_rayTracedGI","1");
 cvars.add("g_nightmare","1");cvars.add("customUserVariable","old",CVAR_ARCHIVE);
 const char*input=R"(+set fs_basepath "C:\Games With Spaces\Doom" +set fs_savepath "D:\Player Saves\" +set r_graphicsAPI dx12 +set r_streamlineEnable 1 +set r_neuralCompatibilityEnable 1 +set r_neuralBackend 3 +exec neural_dogfood.cfg +set r_fullscreen -2 +set r_windowWidth 2560 +set r_hdrOutput 1 +set r_rayTracedGI 0 +set g_nightmare 1 +set customUserVariable "keep me" +exec "my config.cfg")";
 const idStr command=argc>1?idStr(input):Sys_SettingsRelaunchCommandLine(input);idCmdArgs output(command.c_str(),true);
 require(command.find("neural_dogfood.cfg")==std::string::npos,"original generated settings replayed");
 require(setting(output,"fs_basepath")==R"(C:\Games With Spaces\Doom)"&&setting(output,"fs_savepath")==R"(D:\Player Saves\)","quoted install/save path changed");
 for(auto key:{"r_fullscreen","r_windowWidth","r_hdrOutput","r_rayTracedGI"})require(setting(output,key)=="absent","one-time preference seed replayed");
 require(setting(output,"r_neuralBackend")=="2","old runtime reconstruction replayed");
 require(setting(output,"r_streamlineEnable")=="1"&&setting(output,"r_neuralCompatibilityEnable")=="1"&&setting(output,"r_graphicsAPI")=="dx12","SDK/NR startup boundary lost");
 require(setting(output,"g_nightmare")=="1"&&setting(output,"customUserVariable")=="keep me","progress or custom argument dropped");
 require(command.find("my config.cfg")!=std::string::npos,"unrelated explicit config removed");
 cvars.Find("r_neuralBackend")->value="3";
 const idStr second=Sys_SettingsRelaunchCommandLine(command.c_str());idCmdArgs again(second.c_str(),true);
 require(setting(again,"r_neuralBackend")=="3"&&setting(again,"sys_neuralLauncherSession")=="1","second restart replayed previous backend");
 require(setting(again,"fs_savepath")==R"(D:\Player Saves\)","second restart altered save path");
 for(auto input:{"+exec other.cfg +set r_windowWidth 2560","+exec base/neural_dogfood.cfg +set r_hdrOutput 1","+exec neural_dogfood.cfg.bak +set r_hdrOutput 1"})require(Sys_SettingsRelaunchCommandLine(input)==input,"filter affected a non-launcher command line");
 std::cout<<"PASS: actual relaunch filter retains quoted paths/startup state, removes old settings seeds, preserves ordinary launches\n";
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
'''
with tempfile.TemporaryDirectory(prefix='neuraldoom-relaunch-') as directory:
    output = pathlib.Path(directory)
    cpp, exe = output / 'relaunch.cpp', output / 'relaunch.exe'
    cpp.write_text(shim + implementation + checks, encoding='utf-8')
    subprocess.run(['cl', '/nologo', '/EHsc', '/std:c++17', str(cpp),
                    '/Fe:' + str(exe), '/Fo:' + str(output / 'relaunch.obj')], check=True, cwd=output)
    subprocess.run([str(exe)], check=True)
    original = subprocess.run([str(exe), '--original'], capture_output=True, text=True)
    assert original.returncode != 0 and 'original generated settings replayed' in original.stderr
    print('PASS: original raw command-line replay rejected')
