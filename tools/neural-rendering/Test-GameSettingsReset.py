"""Run the actual preference reset/filter and pending-save lifecycle against CPU fixtures."""
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
source = (root / 'neo/framework/PlayerProfile.cpp').read_text(encoding='utf-8')
manager = (root / 'neo/sys/sys_profile.cpp').read_text(encoding='utf-8')
menu = (root / 'neo/d3xp/menus/MenuScreen_Shell_SystemOptions.cpp').read_text(encoding='utf-8')
assert 'if( !resetSettings ) { idKeyInput::SetBinding' in source
assert 'if( !resetSettings ) { ExecConfig( false ); }' in source
assert 'profile->CompletePendingSettingsReset();' in body(manager, 'void idProfileMgr::OnSaveSettingsCompleted')
assert 'if( idPlayerProfile::HasPendingSettingsReset() )' in body(manager, 'void idProfileMgr::Pump()')
assert 'if( accept ) { screen->RestoreDefaults(); }' in menu
assert 'idSWFScriptFunction_RestoreSettings( this, false )' in menu
assert 'if( fieldIndex == SYSTEM_FIELD_RESTORE_DEFAULTS ) { return "Confirm..."; }' in menu
assert 'if( defaultsRestored ) { return true; }' in body(menu, 'bool idMenuScreen_Shell_SystemOptions::idMenuDataSource_SystemSettings::IsRestartRequired()')

shim = r'''
#include <string>
#include <vector>
#include <map>
#include <cstring>
#include <iostream>
#include <stdexcept>
#define ARRAY_COUNT(a) (sizeof(a)/sizeof((a)[0]))
enum {CVAR_STATIC=1,CVAR_ARCHIVE=2,CVAR_INIT=4,CVAR_ROM=8,CVAR_SERVERINFO=16,CVAR_NETWORKSYNC=32,ANTI_ALIASING_TAA=2,CMD_EXEC_NOW=0};
struct idStr:std::string {using std::string::string;idStr(const std::string&s):std::string(s){}operator const char*()const{return c_str();}static int Icmp(const char*a,const char*b){return _stricmp(a,b);}};
struct idKeyValue {idStr key,value;const idStr&GetKey()const{return key;}const idStr&GetValue()const{return value;}};
struct idDict {std::vector<idKeyValue> entries;int GetNumKeyVals()const{return int(entries.size());}const idKeyValue*GetKeyVal(int i)const{return &entries.at(i);}void Delete(const char*key){std::string copy=key;for(auto i=entries.begin();i!=entries.end();++i)if(i->key==copy){entries.erase(i);return;}}void Set(const char*k,const char*v){for(auto&e:entries)if(e.key==k){e.value=v;return;}entries.push_back({k,v});}void SetBool(const char*k,bool v){Set(k,v?"1":"0");}const char*Get(const char*k){for(auto&e:entries)if(e.key==k)return e.value.c_str();return "missing";}};
struct idCVar {std::string name,value,defaults;int flags;int GetFlags()const{return flags;}const char*GetName()const{return name.c_str();}const char*GetDefaultString()const{return defaults.c_str();}void SetString(const char*s){value=s;}};
struct CVars {std::map<std::string,idCVar> vars;int modified=0;idCVar*Find(const char*k){auto it=vars.find(k);return it==vars.end()?nullptr:&it->second;}const char*GetCVarString(const char*k){auto p=Find(k);return p?p->value.c_str():"";}int GetCVarInteger(const char*k){return atoi(GetCVarString(k));}bool GetCVarBool(const char*k){auto p=Find(k);return p&&p->value!="0";}void SetCVarInteger(const char*k,int v){auto p=Find(k);if(p)p->value=std::to_string(v);}void SetCVarBool(const char*k,bool v){SetCVarInteger(k,v);}void SetModifiedFlags(int f){modified|=f;}void SetCVarsFromDict(const idDict&d){for(auto&e:d.entries){auto p=Find(e.key);if(p)p->SetString(e.value);}}void MoveCVarsToDict(int flags,idDict&d){for(auto&p:vars)if(p.second.flags&flags)d.entries.push_back({p.first,p.second.value});}void add(const char*k,const char*v,const char*def,int flags=CVAR_STATIC|CVAR_ARCHIVE){vars[k]={k,v,def,flags};}} cvars;
CVars*cvarSystem=&cvars;
struct Commands{std::vector<std::string>calls;void BufferCommandText(int,const char*s){calls.push_back(s);}} commands;Commands*cmdSystem=&commands;
struct Files{std::vector<std::string>removed;void RemoveFile(const char*s){removed.push_back(s);}} files;Files*fileSystem=&files;
struct Common{void Printf(const char*,...){}} commonInstance;Common*common=&commonInstance;
bool sdk=true,pending=true;int reconstruction=-1;
bool R_StreamlineIsDLSSSupported(){return sdk;}int R_NeuralReconstructionMode(){return cvars.GetCVarInteger(cvars.GetCVarBool("r_neuralCompatibilityEnable")?"r_neuralNRReconstructionMode":"r_neuralReconstructionMode");}void R_SetNeuralReconstructionMode(int mode){reconstruction=mode;cvars.SetCVarInteger(cvars.GetCVarBool("r_neuralCompatibilityEnable")?"r_neuralNRReconstructionMode":"r_neuralReconstructionMode",mode);cvars.SetCVarInteger("r_neuralBackend",mode==0?0:mode==1?2:3);}
struct idPlayerProfile {
 enum {IDLE,SAVING,LOADING,SAVE_REQUESTED,ERR};int state=IDLE,requestedState=IDLE;bool settingsResetAwaitingSave=false,dirty=false;
 bool leftyFlip=true,customConfig=true;int configSet=3;unsigned long long achievementBits=0x12345678,achievementBits2=0xabcdef;
 int dlcReleaseVersion=17;std::vector<int>stats={42,77,99};int saves=0,bindingsReset=0;
 bool RestoreSettingsDefaults();static bool IsResettablePreference(const idCVar*);static bool HasPendingSettingsReset(){return pending;}bool ApplyPendingSettingsReset();void CompletePendingSettingsReset();
 void ExecConfig(bool save,bool force){if(!save||!force)throw std::runtime_error("bindings not explicitly reset");bindingsReset++;}
 void SaveSettings(bool);void MarkDirty(bool d){dirty=d;}bool IsDirty(){return dirty;}int GetRequestedState(){return requestedState;}void SetRequestedState(int s){requestedState=s;if(s==SAVE_REQUESTED)saves++;}
};
void require(bool v,const char*message){if(!v)throw std::runtime_error(message);}
'''
implementation = (
    'bool idPlayerProfile::IsResettablePreference(const idCVar* cvar)' + body(source, 'bool idPlayerProfile::IsResettablePreference')
    + 'bool idPlayerProfile::RestoreSettingsDefaults()' + body(source, 'bool idPlayerProfile::RestoreSettingsDefaults()')
    + 'bool idPlayerProfile::ApplyPendingSettingsReset()' + body(source, 'bool idPlayerProfile::ApplyPendingSettingsReset()')
    + 'void idPlayerProfile::CompletePendingSettingsReset()' + body(source, 'void idPlayerProfile::CompletePendingSettingsReset()')
    + 'void idPlayerProfile::SaveSettings(bool forceDirty)' + body(source, 'void idPlayerProfile::SaveSettings(bool'.replace('(bool', '( bool'))
    + 'bool IsResettablePreference(const idCVar* cvar){return idPlayerProfile::IsResettablePreference(cvar);}'
    + 'void filterProfile(idDict& cvarDict)' + body(source, 'if( resetSettings )')
)
checks = r'''
int main(){try{
 cvars.add("r_exposure","7","0.5");cvars.add("g_nightmare","1","0");cvars.add("g_roeNightmare","0","0");cvars.add("g_leNightmare","0","0");
 cvars.add("r_hdrOutput","1","0");cvars.add("r_neuralBackend","3","0",CVAR_STATIC);cvars.add("r_antiAliasing","0","2");
 cvars.add("r_neuralReconstructionMode","2","1");cvars.add("r_neuralNRReconstructionMode","4","1");cvars.add("r_neuralLaunchProfile","2","-1");
 cvars.add("r_fullscreen","0","0");cvars.add("r_windowWidth","2560","1280");cvars.add("r_windowHeight","720","720");cvars.add("r_vidMode","0","0");
 cvars.add("sys_useGOGPath","1","0");cvars.add("r_streamlineEnable","1","0",CVAR_STATIC|CVAR_INIT|CVAR_ARCHIVE);
 cvars.add("r_neuralCompatibilityEnable","1","0",CVAR_STATIC|CVAR_INIT|CVAR_ARCHIVE);
 cvars.add("r_graphicsAPI","vulkan","dx12",CVAR_STATIC|CVAR_INIT|CVAR_ARCHIVE);
 cvars.add("si_map","custom","-1",CVAR_STATIC|CVAR_ARCHIVE|CVAR_SERVERINFO);
 cvars.add("customUserVariable","retain","",CVAR_ARCHIVE);cvars.add("r_neuralDebug","2","0",CVAR_STATIC);
 for(auto k:{"r_rayTracedAO","r_rayTracedContactShadows","r_rayTracedGI","r_rayTracedReflections"})cvars.add(k,"0","0");
 idDict loaded;loaded.entries={{"r_exposure","9"},{"g_nightmare","0"},{"g_roeNightmare","1"},{"g_leNightmare","0"}};filterProfile(loaded);
 require(std::string(loaded.Get("r_exposure"))=="missing","old profile preference reapplied");
 require(std::string(loaded.Get("g_nightmare"))=="1"&&std::string(loaded.Get("g_roeNightmare"))=="1","local/profile unlock union lost");
 idPlayerProfile busy;busy.state=idPlayerProfile::SAVING;require(!busy.RestoreSettingsDefaults()&&busy.bindingsReset==0,"reset modified saving profile");
 idPlayerProfile p;require(p.ApplyPendingSettingsReset(),"pending reset not applied");
 require(p.achievementBits==0x12345678&&p.achievementBits2==0xabcdef&&p.dlcReleaseVersion==17&&p.stats==std::vector<int>({42,77,99}),"progress changed");
 require(cvars.Find("g_nightmare")->value=="1"&&cvars.Find("sys_useGOGPath")->value=="1","progress/install path reset");
 for(auto k:{"r_streamlineEnable","r_neuralCompatibilityEnable"})require(cvars.Find(k)->value=="1","live startup boundary changed");
 require(cvars.Find("r_graphicsAPI")->value=="vulkan"&&cvars.Find("si_map")->value=="custom"&&cvars.Find("customUserVariable")->value=="retain","protected cvar changed");
 require(cvars.Find("r_exposure")->value=="0.5"&&cvars.Find("r_neuralDebug")->value=="0","defaults not restored");
 require(cvars.Find("r_hdrOutput")->value=="1"&&cvars.Find("r_windowWidth")->value=="2560"&&cvars.Find("r_neuralLaunchProfile")->value=="2","new launcher display/profile choice lost");
 require(!p.leftyFlip&&!p.customConfig&&p.configSet==0&&p.bindingsReset==1&&p.saves==1,"binding preferences not reset/saved");
 require(reconstruction==4&&cvars.Find("r_neuralBackend")->value=="3","pending reset lost selected DLSS Performance");
#if defined(USE_RAYTRACING)
 for(auto k:{"r_rayTracedAO","r_rayTracedContactShadows","r_rayTracedGI","r_rayTracedReflections"})require(cvars.Find(k)->value=="1","shipped ray features not restored");
#endif
 require(commands.calls.size()==1&&commands.calls[0]=="exec neural_rtx_contrast.cfg\n","shipped lighting config not executed");
 require(files.removed.empty()&&p.settingsResetAwaitingSave,"marker cleared before save completion");
 p.CompletePendingSettingsReset();p.CompletePendingSettingsReset();require(files.removed==std::vector<std::string>{"neural_settings_reset.pending"},"marker not consumed exactly once");
 idPlayerProfile corrupt;corrupt.state=idPlayerProfile::ERR;corrupt.SaveSettings(true);require(corrupt.requestedState==idPlayerProfile::IDLE&&!corrupt.dirty&&corrupt.saves==0,"volume change overwrote unreadable profile after reset refused");
 idPlayerProfile inGame;require(inGame.RestoreSettingsDefaults()&&reconstruction==1&&cvars.Find("r_hdrOutput")->value=="0"&&cvars.Find("r_windowWidth")->value=="1280"&&cvars.Find("r_neuralLaunchProfile")->value=="-1","in-game reset did not restore full preference baseline");
 pending=false;idPlayerProfile noRequest;require(!noRequest.ApplyPendingSettingsReset()&&noRequest.saves==0,"ordinary startup reset preferences");
 sdk=false;cvars.SetCVarBool("r_neuralCompatibilityEnable",false);idPlayerProfile native;require(native.RestoreSettingsDefaults()&&cvars.Find("r_neuralBackend")->value=="0","native reset enabled unavailable SDK");
 std::cout<<"PASS: actual reset/filter preserve progress and startup state, restore bindings/settings, consume marker after save only\n";
}catch(const std::exception&e){std::cerr<<e.what();return 1;}}
'''
with tempfile.TemporaryDirectory(prefix='neuraldoom-settings-') as directory:
    output = pathlib.Path(directory)
    for ray in (False, True):
        cpp, exe = output / 'settings.cpp', output / 'settings.exe'
        cpp.write_text(shim + implementation + checks, encoding='utf-8')
        subprocess.run(['cl', '/nologo', '/EHsc', '/std:c++17', *(['/DUSE_RAYTRACING'] if ray else []),
                        str(cpp), '/Fe:' + str(exe), '/Fo:' + str(output / 'settings.obj')], check=True, cwd=output)
        subprocess.run([str(exe)], check=True)
