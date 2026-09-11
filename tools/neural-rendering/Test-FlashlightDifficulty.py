"""Exercise the actual flashlight battery update block with deterministic game ticks.
Run from an MSVC developer shell: python tools/neural-rendering/Test-FlashlightDifficulty.py
"""
import pathlib, subprocess, tempfile
source = pathlib.Path('neo/d3xp/Player.cpp').read_text()
start = source.index('\t// Flashlight has an infinite battery in multiplayer.')
end = source.index('\n\tif( hud )', start)
block = source[start:end]
shim = r'''
#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <iostream>
struct CVar { int value; int GetInteger()const{return value;} float GetFloat()const{return float(value);} };
CVar flashlight_difficulty{1}, flashlight_batteryDrainTimeMS{30000}, flashlight_batteryChargeTimeMS{3000};
template<class T> T Max(T a,T b){return std::max(a,b);}
namespace idMath { int Ftoi(float f){return int(f);} }
struct Common {bool mp=false; bool IsMultiplayer(){return mp;}} commonStorage, *common=&commonStorage;
struct {int time=0,previousTime=0;} gameLocal;
struct Lamp {bool lightOn=true; Lamp* GetEntity(){return this;}};
struct Player {
 Lamp flashlight; int flashlightBattery=30000; float flashlightBatteryFraction=0;
 int idealWeapon=0,weapon_flashlight=1,classic=0;
 int UsesClassicFlashlight(){return classic;}
 void FlashlightOff(){flashlight.lightOn=false;}
 void NextWeapon(){idealWeapon=0;}
 void update(){
'''
checks = r'''
 }
};
void check(bool ok){if(!ok)throw std::runtime_error("flashlight timing regression");}
int main(){
 const int drainTimes[]={40000,30000,20000,15000},chargeTimes[]={2250,3000,6000,12000};
 for(int step: {4,8,16,33})for(int difficulty=0;difficulty<4;difficulty++){
  flashlight_difficulty.value=difficulty; Player p;
  int elapsed=0; while(p.flashlight.lightOn && elapsed<50000){gameLocal.previousTime=elapsed; elapsed+=step;gameLocal.time=elapsed;p.update();}
  check(std::abs(elapsed-drainTimes[difficulty])<=step);check(p.flashlightBattery==0);
  elapsed=0;while(p.flashlightBattery<30000 && elapsed<20000){gameLocal.previousTime=elapsed;elapsed+=step;gameLocal.time=elapsed;p.update();}
  check(std::abs(elapsed-chargeTimes[difficulty])<=step);check(p.flashlightBattery==30000 && p.flashlightBatteryFraction==0);
 }
 gameLocal.previousTime=0;gameLocal.time=16;
 Player p;p.classic=1;p.idealWeapon=1;p.update();check(p.flashlightBattery==30000);
 common->mp=true;p.classic=0;p.update();check(p.flashlightBattery==30000);common->mp=false;
 flashlight_batteryDrainTimeMS.value=-1;p.update();check(p.flashlight.lightOn);
 flashlight_batteryDrainTimeMS.value=30000;flashlight_batteryChargeTimeMS.value=0;
 p.flashlightBattery=0;p.flashlight.lightOn=false;p.update();check(p.flashlightBattery==30000);
 // A custom recharge duration longer than capacity must not round up to a 1x rate.
 flashlight_batteryChargeTimeMS.value=60000;flashlight_difficulty.value=1;
 p.flashlightBattery=0;gameLocal.time=1000;p.update();check(p.flashlightBattery==500);
 std::cout<<"PASS: all four presets at 4/8/16/33ms, depletion/recharge clamps, classic, multiplayer, unlimited and custom recharge\n";
}
'''
with tempfile.TemporaryDirectory(prefix='neuraldoom-flashlight-') as tmp:
    root=pathlib.Path(tmp); cpp=root/'test.cpp'; exe=root/'test.exe'
    cpp.write_text(shim+block+checks)
    subprocess.run(['cl','/nologo','/EHsc','/std:c++17',str(cpp),'/Fe:'+str(exe),'/Fo:'+str(root/'test.obj')],check=True,cwd=root)
    subprocess.run([str(exe)],check=True)
