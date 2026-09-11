"""Execute actual click and arrow-repeater selection blocks after scrolling."""
import pathlib,subprocess,tempfile
s=pathlib.Path('neo/d3xp/menus/MenuScreen_Shell_SystemOptions.cpp').read_text(encoding='utf-8')
start=s.index('\t\t\tif( parms.Num() == 0 )');end=s.index('\n\t\t\tswitch( parms[0].ToInteger() )',start)
block=s[start:end]
start=s.index('\t\t\tif( parms.Num() == 4 )',s.index('case WIDGET_ACTION_START_REPEATER:'))
end=s.index('\n\t\t\tbreak;',start)
repeat=s[start:end]
shim=r"""
#include <stdexcept>
#include <iostream>
struct Arg{int value;int ToInteger()const{return value;}};
struct Args{int size;Arg arg;int Num()const{return size;}const Arg& operator[](int)const{return arg;}};
struct Options{int focus,offset,view,total;int GetFocusIndex(){return focus;}int GetViewOffset(){return offset;}int GetTotalNumberOfOptions(){return total;}void SetViewIndex(int i){if(i<0||i>=total)throw std::runtime_error("view index outside list");view=i;}void SetFocusIndex(int i){if(i<0||i>=total)throw std::runtime_error("focus outside list");focus=i;}};
"""
functions=('bool select(Options* options,const Args& parms){'+block+'return true;}\n'
           +'bool repeat(Options* options,const Args& parms){'+repeat+'return true;}\n'
           +'bool originalRepeat(Options* options,const Args& parms){'
           +repeat.replace('options->SetViewIndex( selectionIndex );',
                           'options->SetViewIndex( options->GetViewOffset() + selectionIndex );')+'return true;}\n')
checks=r"""
int main(int argc,char**){try{
for(int offset=0;offset<=33;offset++)for(int row=0;row<8;row++){
 int target=offset+row;Options options{offset,offset,offset,41};Args args{1,{target}};
 select(&options,args);if(options.focus!=target || options.view!=target)throw std::runtime_error("click offset applied twice");
 options={offset,offset,offset,41};args.size=4;
 if(argc>1)originalRepeat(&options,args);else repeat(&options,args);
 if(options.focus!=target || options.view!=target)throw std::runtime_error("arrow offset applied twice");
}
Options options{3,0,3,40};select(&options,Args{0,{99}});select(&options,Args{1,{-1}});select(&options,Args{1,{40}});
repeat(&options,Args{4,{-1}});repeat(&options,Args{4,{40}});
if(options.focus!=3||options.view!=3)throw std::runtime_error("invalid input changed selection");
std::cout<<"PASS: 544 click/arrow selections, final reset row, empty and invalid commands\n";
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
"""
with tempfile.TemporaryDirectory(prefix='neuraldoom-menu-') as tmp:
 root=pathlib.Path(tmp);src=root/'selection.cpp';exe=root/'selection.exe';src.write_text(shim+functions+checks,encoding='utf-8')
 subprocess.run(['cl','/nologo','/EHsc','/std:c++17',str(src),'/Fe:'+str(exe),'/Fo:'+str(root/'selection.obj')],check=True,cwd=root)
 subprocess.run([str(exe)],check=True)
 old=subprocess.run([str(exe),'--original-arrow'],capture_output=True,text=True)
 assert old.returncode!=0 and 'offset applied twice' in old.stderr, 'Original double-offset must fail'
 print('PASS: original arrow-repeater double-offset rejected')
