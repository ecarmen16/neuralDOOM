"""Compile actual dynamic-scene collection code against bounded CPU fixtures.
Run in an MSVC developer environment. No game, assets or GPU required.
"""
import argparse,pathlib,subprocess,tempfile
parser=argparse.ArgumentParser();parser.add_argument('--source',type=pathlib.Path,default=pathlib.Path('neo/renderer/RayTracingDiagnostic.cpp'));a=parser.parse_args()
s=a.source.read_text(encoding='utf-8');start=s.index('\t\tstd::vector<idVec3> points;',s.index('bool UpdateDynamic('));end=s.index('\n\t\tif( elements.empty() && !hadDynamic )',start)
block=s[start:end]
shim=r"""
#include <vector>
#include <cmath>
#include <stdexcept>
#include <iostream>
#include <limits>
using uint32=unsigned int;
struct idVec2 {float x=0,y=0;};
struct idVec3 {float x=0,y=0,z=0;float operator[](int i)const{return (&x)[i];}};
struct idVec4 {float x,y,z,w;idVec4(float a,float b,float c,float d):x(a),y(b),z(c),w(d){}};
struct CVar {bool enabled=true;bool GetBool()const{return enabled;}};
CVar r_rayTracingDynamicGeometry,r_rayTracingSkinnedGeometry,r_rayTracingPlayerShadows;
struct rtShadowPolicy_t {uint32 shadowOnly,suppressLight;};
struct rayDynamicSurface_t {rayDynamicSurface_t* next=nullptr;idVec3* positions=nullptr;idVec2* texcoords=nullptr;uint32* indices=nullptr;int numVerts=0,numIndexes=0;bool castsShadow=true,skinned=false,shadowOnly=false;int suppressShadowInLightID=0;};
struct viewEntity_t {viewEntity_t* next=nullptr;rayDynamicSurface_t* raySurfaces=nullptr;};
struct viewDef_t {viewEntity_t* viewEntitys=nullptr;};
constexpr uint32 RT_DYNAMIC_VERTICES=6,RT_DYNAMIC_INDICES=6,RT_DYNAMIC_SURFACES=2;
uint32 staticVertexCount=17,dynamicSurfaceCount=0,dynamicTriangleCount=0,dynamicSkinnedCount=0,dynamicSkippedCount=0,dynamicHiddenCount=0;
std::vector<rtShadowPolicy_t> gotPolicies;
std::vector<idVec3> gotPoints;std::vector<uint32> gotIndices;
void collect(const viewDef_t* view,bool shadowsOnly,std::vector<idVec4>* uv,std::vector<const rayDynamicSurface_t*>* accepted,uint32 firstMaterial){
"""
checks=r"""
gotPoints=points;gotIndices=elements;gotPolicies=policies;
}
void check(bool b){if(!b)throw std::runtime_error("geometry contract mismatch");}
int main(){try{
idVec3 p[]={{1,2,3},{4,5,6},{7,8,9}};idVec2 t[]={{0,0},{1,0},{0,1}};uint32 i[]={2,0,1};
rayDynamicSurface_t b{nullptr,p,t,i,3,3,false,true},a{&b,p,t,i,3,3,true,false};
viewEntity_t entity{nullptr,&a};viewDef_t view{&entity};std::vector<idVec4> uv;std::vector<const rayDynamicSurface_t*> accepted;
collect(&view,false,&uv,&accepted,101);
check(dynamicSurfaceCount==2 && dynamicTriangleCount==2 && dynamicSkinnedCount==1);
check(gotIndices==std::vector<uint32>({19,17,18,22,20,21}));
check(uv.size()==6 && uv[0].z==101 && uv[3].z==102 && uv[4].x==1 && accepted[1]==&b);
collect(&view,true,&uv,&accepted,101);check(dynamicSurfaceCount==1 && accepted[0]==&a);
r_rayTracingSkinnedGeometry.enabled=false;collect(&view,false,&uv,&accepted,101);check(dynamicSurfaceCount==1);
r_rayTracingSkinnedGeometry.enabled=true;
b.shadowOnly=true;b.castsShadow=true;b.suppressShadowInLightID=77;
collect(&view,true,&uv,&accepted,101);check(dynamicHiddenCount==1 && gotPolicies.size()==2 && gotPolicies[1].shadowOnly==1 && gotPolicies[1].suppressLight==77);
collect(&view,false,nullptr,nullptr,0);check(dynamicHiddenCount==0 && dynamicSurfaceCount==1);
r_rayTracingPlayerShadows.enabled=false;collect(&view,true,&uv,&accepted,101);check(dynamicSurfaceCount==1);
r_rayTracingPlayerShadows.enabled=true;r_rayTracingDynamicGeometry.enabled=false;
collect(&view,true,&uv,&accepted,101);check(dynamicSurfaceCount==1 && dynamicHiddenCount==1 && accepted[0]==&b);
collect(&view,false,&uv,&accepted,101);check(dynamicSurfaceCount==1 && dynamicHiddenCount==1);
collect(&view,false,nullptr,nullptr,0);check(dynamicSurfaceCount==0);
r_rayTracingPlayerShadows.enabled=false;collect(&view,true,&uv,&accepted,101);check(dynamicSurfaceCount==0);
r_rayTracingDynamicGeometry.enabled=true;
r_rayTracingPlayerShadows.enabled=true;b.shadowOnly=false;b.castsShadow=false;
rayDynamicSurface_t c=b;b.next=&c;collect(&view,false,&uv,&accepted,101);check(dynamicSurfaceCount==2 && dynamicSkippedCount==1 && gotIndices.size()==6);
b.next=nullptr;p[0].x=std::numeric_limits<float>::quiet_NaN();collect(&view,false,&uv,&accepted,101);check(gotPoints.empty() && dynamicSkippedCount==2);
p[0].x=1;r_rayTracingDynamicGeometry.enabled=false;collect(&view,false,&uv,&accepted,101);check(gotIndices.empty() && uv.empty() && accepted.empty());
r_rayTracingDynamicGeometry.enabled=true;view.viewEntitys=nullptr;collect(&view,false,&uv,&accepted,101);check(gotIndices.empty() && dynamicSurfaceCount==0);
std::cout<<"PASS: global vertex offsets, per-surface materials, UVs, shadow policy, skinned toggle, budgets, invalid geometry, disabled and empty scenes\n";
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
"""
with tempfile.TemporaryDirectory(prefix='neuraldoom-dynamic-') as tmp:
 root=pathlib.Path(tmp);src=root/'dynamic.cpp';exe=root/'dynamic.exe';src.write_text(shim+block+checks,encoding='utf-8')
 subprocess.run(['cl','/nologo','/EHsc','/std:c++17',str(src),'/Fe:'+str(exe),'/Fo:'+str(root/'dynamic.obj')],check=True,cwd=root)
 subprocess.run([str(exe)],check=True)

# Exercise the actual frontend snapshot, including current-pose skinning and deep copies.
f=pathlib.Path('neo/renderer/tr_frontend_addmodels.cpp').read_text(encoding='utf-8')
start=f.index('static void R_SnapshotDynamicRaySurface(');end=f.index('\nvoid R_SetupDrawSurfJoints(',start)
frontend=f[start:end]
front_shim=r"""
#include <vector>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <stdexcept>
#include <iostream>
using triIndex_t=unsigned int;
struct idVec2 {float x=0,y=0;};
struct idVec4 {float x,y,z,w;idVec4(float a,float b,float c,float d):x(a),y(b),z(c),w(d){}};
struct idVec3 {float x=0,y=0,z=0;};
struct idJointMat {
 float a[12]={1,0,0,0,0,1,0,0,0,0,1,0};
 static void Mul(idJointMat& d,const idJointMat& s,float w){for(int i=0;i<12;i++)d.a[i]=s.a[i]*w;}
 static void Mad(idJointMat& d,const idJointMat& s,float w){for(int i=0;i<12;i++)d.a[i]+=s.a[i]*w;}
 idVec3 operator*(idVec4 p)const{return {a[0]*p.x+a[1]*p.y+a[2]*p.z+a[3],a[4]*p.x+a[5]*p.y+a[6]*p.z+a[7],a[8]*p.x+a[9]*p.y+a[10]*p.z+a[11]};}
};
struct idDrawVert {idVec3 xyz;unsigned char color[4]={0,1,0,0},color2[4]={128,127,0,0};idVec2 uv;idVec2 GetTexCoord()const{return uv;}};
struct idRenderModelStatic {idJointMat* jointsInverted;int numInvertedJoints;};
struct srfTriangles_t {idDrawVert* verts;triIndex_t* indexes;int numVerts,numIndexes;idRenderModelStatic* staticModelWithJoints;};
constexpr int MC_OPAQUE=0,DFRM_NONE=0,MF_NOSELFSHADOW=1,FRAME_ALLOC_DRAW_SURFACE=0;
struct idMaterial {bool noSelfShadow=false;bool ReceivesLighting()const{return true;}int Coverage()const{return 0;}int Deform()const{return 0;}bool HasSubview()const{return false;}bool IsPortalSky()const{return false;}bool SurfaceCastsShadow()const{return true;}bool TestMaterialFlag(int)const{return noSelfShadow;}};
struct rayDynamicSurface_t {rayDynamicSurface_t* next;idVec3* positions;idVec2* texcoords;triIndex_t* indices;int numVerts,numIndexes;const idMaterial* material;const float* shaderRegisters;bool castsShadow,skinned,shadowOnly;int suppressShadowInLightID;};
struct viewEntity_t {rayDynamicSurface_t* raySurfaces=nullptr;int rayVertexCount=0;bool weaponDepthHack=false,isGuiSurface=false;float modelDepthHack=0;float modelMatrix[16]={0,1,0,0,-1,0,0,0,0,0,1,0,10,20,30,1};};
struct CVar {bool enabled=true;bool GetBool()const{return enabled;}};
CVar r_useGPUSkinning,r_rayTracingSkinnedGeometry,r_rayTracingPlayerShadows,r_rayTracingDynamicGeometry;
CVar r_skipSuppress{false};
bool wanted=true;bool R_WantDynamicRayGeometry(){return wanted;}
std::vector<void*> allocations;
void* R_FrameAlloc(size_t size,int){void* p=std::malloc(size);allocations.push_back(p);return p;}
void R_LocalPointToGlobal(const float* m,const idVec3& p,idVec3& q){q={m[0]*p.x+m[4]*p.y+m[8]*p.z+m[12],m[1]*p.x+m[5]*p.y+m[9]*p.z+m[13],m[2]*p.x+m[6]*p.y+m[10]*p.z+m[14]};}
"""
selection=f[f.index('\tconst bool shadowSuppressed ='):f.index('\tconst bool addInteractions =')]
frontend += r"""
bool hiddenGate(bool modelIsVisible, int surfaceView, int shadowView, bool noShadow, int viewID) {
 struct Parms {int suppressSurfaceInViewID,suppressShadowInViewID,suppressShadowInLightID;bool noShadow;} parms{surfaceView,shadowView,77,noShadow};
 struct View {struct {int viewID;} renderView;} view{{viewID}};
 const auto* renderEntity=&parms;const auto* viewDef=&view;
"""+selection+"return hiddenPlayerShadow; }\n"
front_checks=r"""
void check(bool b){if(!b)throw std::runtime_error("snapshot mismatch");}
int main(){try{
check(hiddenGate(false,1,0,false,1));
check(!hiddenGate(true,1,0,false,1) && !hiddenGate(false,1,1,false,1));
check(!hiddenGate(false,1,0,true,1) && !hiddenGate(false,1,0,false,2));
check(!hiddenGate(false,0,0,false,0));
r_rayTracingPlayerShadows.enabled=false;check(!hiddenGate(false,1,0,false,1));r_rayTracingPlayerShadows.enabled=true;
wanted=false;check(!hiddenGate(false,1,0,false,1));wanted=true;
idDrawVert v[3];v[0].xyz={1,2,3};v[0].uv={0.2f,0.7f};v[1].xyz={2,2,3};v[2].xyz={1,3,3};unsigned i[]={0,1,2};
idMaterial material;float regs[4]={1,1,1,1};srfTriangles_t tri{v,i,3,3,nullptr};viewEntity_t entity;
R_SnapshotDynamicRaySurface(&entity,&tri,&material,regs,false,false);auto* rigid=entity.raySurfaces;
check(rigid && rigid->positions[0].x==8 && rigid->positions[0].y==21 && rigid->positions[0].z==33);
check(!rigid->shadowOnly && rigid->suppressShadowInLightID==0);
check(rigid->castsShadow && !rigid->skinned && rigid->texcoords[0].x==0.2f && rigid->indices[2]==2);
v[0].xyz.x=9;i[0]=2;check(rigid->positions[0].y==21 && rigid->indices[0]==0);v[0].xyz.x=1;i[0]=0;
idJointMat joints[2];joints[1].a[3]=2;idRenderModelStatic model{joints,2};tri.staticModelWithJoints=&model;
R_SnapshotDynamicRaySurface(&entity,&tri,&material,regs,true,true);auto* skin=entity.raySurfaces;
check(skin!=rigid && skin->skinned && !skin->castsShadow && std::abs(skin->positions[0].y-(21+254.0f/255))<0.0001f);
material.noSelfShadow=true;
r_rayTracingDynamicGeometry.enabled=false;
const size_t beforeHidden=allocations.size();
R_SnapshotDynamicRaySurface(&entity,&tri,&material,regs,false,true);check(allocations.size()==beforeHidden);
R_SnapshotDynamicRaySurface(&entity,&tri,&material,regs,false,true,true,77);auto* hidden=entity.raySurfaces;
check(hidden!=skin && hidden->shadowOnly && hidden->castsShadow && hidden->suppressShadowInLightID==77);
r_rayTracingDynamicGeometry.enabled=true;
const size_t before=allocations.size();r_rayTracingSkinnedGeometry.enabled=false;R_SnapshotDynamicRaySurface(&entity,&tri,&material,regs,false,true);check(allocations.size()==before);
r_rayTracingSkinnedGeometry.enabled=true;entity.weaponDepthHack=true;R_SnapshotDynamicRaySurface(&entity,&tri,&material,regs,false,true);check(allocations.size()==before);
entity.weaponDepthHack=false;v[0].color[0]=9;R_SnapshotDynamicRaySurface(&entity,&tri,&material,regs,false,true);check(allocations.size()==before);v[0].color[0]=0;
i[0]=9;R_SnapshotDynamicRaySurface(&entity,&tri,&material,regs,false,true);check(allocations.size()==before);
for(void* p:allocations)std::free(p);
std::cout<<"PASS: rigid world transform, current weighted skin pose, independent frame copies, shadow flags, viewmodel/skin toggles and invalid indices\n";
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
"""
with tempfile.TemporaryDirectory(prefix='neuraldoom-snapshot-') as tmp:
 root=pathlib.Path(tmp);src=root/'snapshot.cpp';exe=root/'snapshot.exe';src.write_text(front_shim+frontend+front_checks,encoding='utf-8')
 subprocess.run(['cl','/nologo','/EHsc','/std:c++17',str(src),'/Fe:'+str(exe),'/Fo:'+str(root/'snapshot.obj')],check=True,cwd=root)
 subprocess.run([str(exe)],check=True)
