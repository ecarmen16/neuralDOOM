"""Compile the actual mouse-hover dispatch block against reference-count fixtures.
No game data, graphics device, or copied runtime required. Run from a VS developer shell.
"""
import argparse, pathlib, subprocess, tempfile
parser=argparse.ArgumentParser()
parser.add_argument('--source',type=pathlib.Path,default=pathlib.Path('neo/swf/SWF_Events.cpp'))
parser.add_argument('--cl',default='cl')
a=parser.parse_args()
s=a.source.read_text(encoding='utf-8')
start=s.rindex('\t\tidSWFScriptObject* hitObject = HitTest(')
end=s.index('\n\t\tif( mouseObject != NULL )',start)
block=s[start:end]
shim=r"""
#include <functional>
#include <stdexcept>
#include <string>
#include <iostream>
struct idSWFParmList {};
struct idSWFScriptObject;
struct Function { std::function<void()> callback; void Call(idSWFScriptObject*,idSWFParmList){ callback(); } };
struct idSWFScriptVar {
 idSWFScriptObject* object=nullptr; Function* function=nullptr;
 idSWFScriptVar()=default;
 idSWFScriptVar(idSWFScriptObject*);
 idSWFScriptVar(Function* f):function(f){}
 idSWFScriptVar(const idSWFScriptVar&);
 ~idSWFScriptVar();
 bool IsFunction() const{return function!=nullptr;}
 Function* GetFunction() const{return function;}
 idSWFScriptObject* GetObject() const{return object;}
};
struct idSWFScriptObject {
 int refs=1; Function *out=nullptr,*over=nullptr;
 void AddRef(){if(refs<=0)throw std::runtime_error("retain after free");++refs;}
 void Release(){if(refs<=0)throw std::runtime_error("double release");--refs;}
 idSWFScriptVar Get(const char* name){if(refs<=0)throw std::runtime_error("GetVariable after free");return idSWFScriptVar(std::string(name)=="onRollOut"?out:over);}
};
idSWFScriptVar::idSWFScriptVar(idSWFScriptObject* p):object(p){if(p)p->AddRef();}
idSWFScriptVar::idSWFScriptVar(const idSWFScriptVar& v):object(v.object),function(v.function){if(object)object->AddRef();}
idSWFScriptVar::~idSWFScriptVar(){if(object)object->Release();}
idSWFScriptObject *hoverObject=nullptr,*nextHit=nullptr;
int mainspriteInstance=0,mouseX=0,mouseY=0;
bool hasHitObject=false;
int swfRenderState_t(){return 0;}
idSWFScriptObject* HitTest(int,int,int,int,void*){return nextHit;}
void dispatch(){bool retVal=false;
"""
checks=r"""
}
void check(bool ok){if(!ok)throw std::runtime_error("reference/callback invariant");}
int main(){try{
 // Roll-out removes the new hit from the display list before roll-over.
 idSWFScriptObject old,next; int calls=0;
 Function out{[&]{next.Release();}},over{[&]{++calls;}};
 old.out=&out;next.over=&over;hoverObject=&old;nextHit=&next;
 dispatch();check(old.refs==0 && next.refs==1 && calls==1 && hoverObject==&next);
 // Same hit does not repeat callbacks or leak an extra reference.
 dispatch();check(next.refs==1 && calls==1);
 nextHit=nullptr;dispatch();check(next.refs==0 && hoverObject==nullptr && !hasHitObject);
 dispatch();check(hoverObject==nullptr);
 // A nested callback consumes/replaces the outgoing hover reference.
 idSWFScriptObject old2,next2,reentrant;hoverObject=&old2;nextHit=&next2;
 Function reenter{[&]{if(hoverObject){hoverObject->Release();hoverObject=nullptr;} hoverObject=&reentrant;}};
 old2.out=&reenter;dispatch();
 check(old2.refs==0 && reentrant.refs==0 && next2.refs==2 && hoverObject==&next2);
 hoverObject->Release();hoverObject=nullptr;next2.Release();
 std::cout<<"PASS: removed hit, stable hover, empty space, reentrant roll-out and balanced references\n";
 return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
"""
with tempfile.TemporaryDirectory(prefix='neuraldoom-swf-') as tmp:
 root=pathlib.Path(tmp);source=root/'hover.cpp';exe=root/'hover.exe'
 source.write_text(shim+block+checks,encoding='utf-8')
 subprocess.run([a.cl,'/nologo','/EHsc','/std:c++17',str(source),'/Fe:'+str(exe),'/Fo:'+str(root/'hover.obj')],check=True,cwd=root)
 subprocess.run([str(exe)],check=True)
