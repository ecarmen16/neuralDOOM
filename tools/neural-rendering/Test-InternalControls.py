"""Execute the shipped safe-key migration against legacy/custom binding fixtures."""
import pathlib
import re
import subprocess
import tempfile

source = pathlib.Path('neo/renderer/RayTracingDiagnostic.cpp').read_text(encoding='utf-8')
start = source.index('CONSOLE_COMMAND_SHIP( neuralInstallKeys,')
body = source[source.index('{', start) + 1:].rsplit('}', 1)[0]
shim = r'''
#include <string>
#include <map>
#include <cstring>
#include <iostream>
#include <stdexcept>
enum {K_F1=1,K_F2,K_F3,K_F4,K_F5,K_F6,K_F7,K_F8,K_F9,K_F10,K_F11,K_F12};
struct idStr { static int Icmp(const char*a,const char*b){return _stricmp(a,b);} };
struct idKeyInput { static std::map<int,std::string> keys; static const char* GetBinding(int k){return keys[k].c_str();} static void SetBinding(int k,const char*s){keys[k]=s;} };
std::map<int,std::string> idKeyInput::keys;
struct Version{int v=0;int GetInteger(){return v;}void SetInteger(int n){v=n;}} r_neuralKeysVersion;
struct Common{void Printf(const char*,...){}} instance;Common*common=&instance;
struct Args{int n;int Argc(){return n;}};
void install(const Args& args){
'''.replace('int Argc(){', 'int Argc()const{')
checks = r'''
}
void require(bool ok){if(!ok)throw std::runtime_error("binding migration regression");}
int main(){try{
auto& k=idKeyInput::keys;
k[5]="savegame quick";k[9]="toggle r_rayTracedReflections; neuralHistoryReset";k[12]="screenshot";
k[6]="toggle r_rayTracedGI; neuralHistoryReset";k[4]="toggle r_rayTracedGI; neuralHistoryReset";
k[1]="custom F1";k[8]="custom F8";
install(Args{2});
require(k[1]=="custom F1"&&k[8]=="custom F8"&&k[6].empty());
require(k[5]=="savegame quick"&&k[9]=="loadgame quick"&&k[12]=="screenshot");
require(k[3]=="rayTracingReflectionToggle"&&k[4]=="rayTracingBounceToggle"&&k[2]=="rayTracingDynamicToggle");
k[3]="";install(Args{2});require(k[3].empty()); // preserve intentional unbinding after first startup
k[6]="custom F6";k[9]="custom F9";install(Args{1});
require(k[3]=="rayTracingReflectionToggle"&&k[6]=="custom F6"&&k[9]=="custom F9");
std::cout<<"PASS: first-use migration, legacy F6/F9 repair, custom keys, intentional unbinding, explicit fill-free action\n";
}catch(const std::exception&e){std::cerr<<e.what();return 1;}}
'''
with tempfile.TemporaryDirectory(prefix='neuraldoom-keys-') as directory:
    root = pathlib.Path(directory)
    cpp, exe = root / 'keys.cpp', root / 'keys.exe'
    cpp.write_text(shim + body + checks, encoding='utf-8')
    subprocess.run(['cl', '/nologo', '/EHsc', '/std:c++17', str(cpp), '/Fe:' + str(exe), '/Fo:' + str(root / 'keys.obj')], check=True, cwd=root)
    subprocess.run([str(exe)], check=True)
defaults = pathlib.Path('base/default.cfg').read_text(encoding='utf-8')
binds = dict(re.findall(r'(?im)^bind\s+(F\d+)\s+"?([^"\r\n]+)', defaults))
assert binds['F5'] == 'savegame quick' and binds['F9'] == 'loadgame quick' and binds['F12'].strip() == 'screenshot'
assert 'F6' not in binds
for key in ('F1', 'F2', 'F3', 'F4', 'F7', 'F8', 'F10', 'F11'):
    assert f'CONSOLE_COMMAND_SHIP( {binds[key]},' in source
print('PASS: default keys preserve Doom controls and reference registered commands')
