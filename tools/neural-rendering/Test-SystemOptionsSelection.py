"""Regression for clicks after scrolling: execute the actual command-selection block."""
import pathlib,subprocess,tempfile
s=pathlib.Path('neo/d3xp/menus/MenuScreen_Shell_SystemOptions.cpp').read_text(encoding='utf-8')
start=s.index('\t\t\tif( parms.Num() == 0 )');end=s.index('\n\t\t\tswitch( parms[0].ToInteger() )',start)
block=s[start:end]
shim=r"""
#include <stdexcept>
#include <iostream>
struct Arg{int value;int ToInteger()const{return value;}};
struct Args{int size;Arg arg;int Num()const{return size;}const Arg& operator[](int)const{return arg;}};
struct Options{int focus,offset,view,total;int GetFocusIndex(){return focus;}int GetViewOffset(){return offset;}int GetTotalNumberOfOptions(){return total;}void SetViewIndex(int i){if(i<0||i>=total)throw std::runtime_error("view index outside list");view=i;}void SetFocusIndex(int i){if(i<0||i>=total)throw std::runtime_error("focus outside list");focus=i;}};
bool select(Options* options,const Args& parms){
"""
checks=r"""
return true;}
int main(){try{
for(int offset=0;offset<=32;offset++)for(int row=0;row<8;row++){
 int target=offset+row;Options options{offset,offset,offset,40};Args args{1,{target}};
 select(&options,args);if(options.focus!=target || options.view!=target)throw std::runtime_error("scroll offset applied twice");
}
Options options{3,0,3,40};select(&options,Args{0,{99}});select(&options,Args{1,{-1}});select(&options,Args{1,{40}});
if(options.focus!=3||options.view!=3)throw std::runtime_error("invalid input changed selection");
std::cout<<"PASS: 264 scrolled selections, first/last rows, empty and invalid commands\n";
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
"""
with tempfile.TemporaryDirectory(prefix='neuraldoom-menu-') as tmp:
 root=pathlib.Path(tmp);src=root/'selection.cpp';exe=root/'selection.exe';src.write_text(shim+block+checks,encoding='utf-8')
 subprocess.run(['cl','/nologo','/EHsc','/std:c++17',str(src),'/Fe:'+str(exe),'/Fo:'+str(root/'selection.obj')],check=True,cwd=root)
 subprocess.run([str(exe)],check=True)
