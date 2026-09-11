// SPDX-License-Identifier: GPL-3.0-or-later
// Optional ray-traced lighting and intersection diagnostics.
#include "precompiled.h"
#pragma hdrstop

#include "RenderCommon.h"
#include "StreamlineIntegration.h"
#include "NeuralTemporal.h"
#include "../framework/KeyInput.h"
#include "../framework/Common_local.h"
#include "../sys/DeviceManager.h"
#include <cmath>
#include <algorithm>
#include <vector>
#include <atomic>

extern DeviceManager* deviceManager;
extern idCVar r_useNewSsaoPass;

idCVar r_rayTracingDynamicGeometry( "r_rayTracingDynamicGeometry", "1", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_BOOL, "include frame-visible opaque moving entities in ray lighting" );
idCVar r_rayTracingSkinnedGeometry( "r_rayTracingSkinnedGeometry", "1", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_BOOL, "include current skinned poses in dynamic ray geometry" );
idCVar r_rayTracedAO( "r_rayTracedAO", "0", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_BOOL, "Experimental native ray-traced AO for static opaque world surfaces; requires USE_RAYTRACING and new SSAO" );
static idCVar r_rayTracedAORadius( "r_rayTracedAORadius", "64", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "Ray-traced AO radius in Doom world units", 1, 256 );
static idCVar r_rayTracedAOStrength( "r_rayTracedAOStrength", "1", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "Ray-traced AO darkening strength", 0, 2 );
static idCVar r_rayTracedAOSamples( "r_rayTracedAOSamples", "8", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_INTEGER, "Ray-traced AO hemisphere samples per pixel", 1, 32 );
static idCVar r_rayTracedContactShadows( "r_rayTracedContactShadows", "0", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_BOOL, "Supplement direct-light shadows with ray-traced contact shadows" );
static idCVar r_rayTracedContactDistance( "r_rayTracedContactDistance", "128", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "Contact-shadow ray reach in Doom world units", 1, 512 );
static idCVar r_rayTracedContactStrength( "r_rayTracedContactStrength", "1", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "Contact-shadow strength", 0, 1 );
static idCVar r_rayTracingDebug( "r_rayTracingDebug", "0", CVAR_RENDERER | CVAR_INTEGER, "0=shaded scene, 1=AO visibility, 2=contact-shadow visibility, 3=indirect material lighting, 4=ray-scene diffuse albedo, 5=reflections, 6=reflection receiver roughness", 0, 6 );
static idCVar r_rayTracedGI( "r_rayTracedGI", "0", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_BOOL, "Experimental material-aware single-bounce diffuse lighting for static opaque world geometry" );
static idCVar r_rayTracedGIStrength( "r_rayTracedGIStrength", "1.125", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "Indirect material lighting intensity", 0, 4 );
static idCVar r_rayTracedGIRadius( "r_rayTracedGIRadius", "384", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "Maximum diffuse bounce distance in Doom world units", 16, 2048 );
static idCVar r_rayTracedGISamples( "r_rayTracedGISamples", "4", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_INTEGER, "Diffuse bounce samples per full-resolution pixel", 1, 16 );
static idCVar r_rayTracedGIEmissive( "r_rayTracedGIEmissive", "2", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "Emissive material contribution to indirect lighting", 0, 8 );

static idCVar r_rayTracedReflections( "r_rayTracedReflections", "0", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_BOOL, "Full-resolution reflections using native material roughness and normal maps" );
static idCVar r_rayTracedReflectionStrength( "r_rayTracedReflectionStrength", "0.65", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "Blend from native probe specular to traced reflections", 0, 1 );
static idCVar r_rayTracedReflectionSamples( "r_rayTracedReflectionSamples", "4", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_INTEGER, "Reflection rays per full-resolution eligible pixel", 1, 16 );
static idCVar r_rayTracedReflectionRoughness( "r_rayTracedReflectionRoughness", "0.7", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "Maximum reflection roughness, with a 0.15 fade into native probes", 0.1, 1 );
static idCVar r_rayTracedReflectionDistance( "r_rayTracedReflectionDistance", "2048", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "Maximum reflection ray distance in Doom world units", 16, 8192 );

void RB_GetShaderTextureMatrix( const float* shaderRegisters, const textureStage_t* texture, float matrix[16] );
void RB_BakeTextureMatrixIntoTexgen( idPlane lightProject[3], const float* textureMatrix );

bool R_WantDynamicRayGeometry()
{
#if defined( USE_RAYTRACING )
	return r_rayTracingDynamicGeometry.GetBool() && ( r_rayTracedAO.GetBool() || r_rayTracedGI.GetBool() || r_rayTracedReflections.GetBool() || r_rayTracedContactShadows.GetBool() );
#else
	return false;
#endif
}

bool R_RayTracingSettingsChanged()
{
	bool changed = false;
#if defined( USE_RAYTRACING )
	idCVar* settings[] = { &r_rayTracingDynamicGeometry, &r_rayTracingSkinnedGeometry, &r_rayTracedAO, &r_rayTracedAORadius, &r_rayTracedAOStrength, &r_rayTracedAOSamples,
		&r_rayTracedContactShadows, &r_rayTracedContactDistance, &r_rayTracedContactStrength,
		&r_rayTracedGI, &r_rayTracedGIStrength, &r_rayTracedGIRadius, &r_rayTracedGISamples, &r_rayTracedGIEmissive, &r_rayTracingDebug, &r_rayTracedReflections, &r_rayTracedReflectionStrength,
		&r_rayTracedReflectionSamples, &r_rayTracedReflectionRoughness, &r_rayTracedReflectionDistance };
	for( idCVar* setting : settings )
	{
		changed |= setting->IsModified();
		setting->ClearModified();
	}
#endif
	return changed;
}

#if defined( USE_RAYTRACING )

namespace
{
static const uint32 RT_DYNAMIC_VERTICES = 131072;
static const uint32 RT_DYNAMIC_INDICES = 393216;
static const uint32 RT_DYNAMIC_SURFACES = 128;
static std::atomic<uint32> dynamicSurfaceCount( 0 ), dynamicTriangleCount( 0 ), dynamicSkinnedCount( 0 ), dynamicSkippedCount( 0 );
struct rtRay_t
{
	idVec3 origin;
	float tMin;
	idVec3 direction;
	float tMax;
	uint32 mask;
	uint32 padding[3];
};

struct rtHit_t
{
	uint32 hit;
	float distance;
	uint32 instance;
	uint32 primitive;
};

static_assert( sizeof( idVec3 ) == 12, "RT vertex format must be float3" );
static_assert( sizeof( rtRay_t ) == 48, "RT ray buffer must match HLSL" );
static_assert( sizeof( rtHit_t ) == 16, "RT result buffer must match HLSL" );

static rtRay_t MakeRay( const idVec3& origin, const idVec3& direction, uint32 mask = 255, float tMin = 0.01f, float tMax = 8192.0f )
{
	rtRay_t ray = {};
	ray.origin = origin;
	ray.direction = direction;
	ray.tMin = tMin;
	ray.tMax = tMax;
	ray.mask = mask;
	return ray;
}

static nvrhi::IDevice* DiagnosticDevice( const char* command )
{
	commonLocal.WaitGameThread();
	nvrhi::IDevice* device = deviceManager ? deviceManager->GetDevice() : nullptr;
	if( !device || device->getGraphicsAPI() != nvrhi::GraphicsAPI::D3D12 ||
		!device->queryFeatureSupport( nvrhi::Feature::RayTracingAccelStruct ) ||
		!device->queryFeatureSupport( nvrhi::Feature::RayQuery ) )
	{
		common->Printf( "%s status=SKIP reason=unsupported-device\n", command );
		return nullptr;
	}
	return device;
}

// Own immutable geometry copies and acceleration structures. Diagnostics use
// this per invocation; gameplay AO retains it until the world is unloaded.
// Automatic NVRHI barriers order upload, BLAS, TLAS, tracing and readback.
class RayQueryDiagnostic
{
public:
	explicit RayQueryDiagnostic( nvrhi::IDevice* value ) : device( value ) {}

	bool Initialize( const std::vector<idVec3>& positions, const std::vector<uint32>& indices,
		std::vector<nvrhi::rt::InstanceDesc>& instances, bool gameplay = false )
	{
		staticVertexCount = positions.size(); staticIndexCount = indices.size();
		dynamicEnabled = gameplay;
		void* shaderBytes = nullptr;
		int shaderSize = fileSystem->ReadFile( "renderprogs2/dxil/rt/ray_query.cs.dxil", &shaderBytes );
		if( shaderSize <= 0 || !shaderBytes )
		{
			if( shaderBytes ) { fileSystem->FreeFile( shaderBytes ); }
			common->Printf( "RT_DIAGNOSTIC_ERROR reason=missing-shader\n" );
			return false;
		}
		nvrhi::ShaderDesc shaderDesc( nvrhi::ShaderType::Compute );
		shaderDesc.debugName = "Native RT diagnostic";
		shader = device->createShader( shaderDesc, shaderBytes, shaderSize );
		fileSystem->FreeFile( shaderBytes );
		if( !shader ) { return false; }

		nvrhi::BufferDesc vertexDesc;
		vertexDesc.byteSize = ( positions.size() + ( gameplay ? RT_DYNAMIC_VERTICES : 0 ) ) * sizeof( idVec3 );
		vertexDesc.isAccelStructBuildInput = true;
		vertexDesc.structStride = sizeof( idVec3 );
		vertexDesc.initialState = nvrhi::ResourceStates::CopyDest;
		vertexDesc.keepInitialState = true;
		vertexDesc.debugName = "RT diagnostic positions";
		vertices = device->createBuffer( vertexDesc );
		nvrhi::BufferDesc indexDesc = vertexDesc;
		indexDesc.byteSize = ( indices.size() + ( gameplay ? RT_DYNAMIC_INDICES : 0 ) ) * sizeof( uint32 );
		indexDesc.structStride = sizeof( uint32 );
		indexDesc.debugName = "RT diagnostic indices";
		indexBuffer = device->createBuffer( indexDesc );
		if( !vertices || !indexBuffer ) { return false; }

		nvrhi::rt::GeometryTriangles triangles;
		triangles.vertexBuffer = vertices;
		triangles.vertexFormat = nvrhi::Format::RGB32_FLOAT;
		triangles.vertexStride = sizeof( idVec3 );
		triangles.vertexCount = static_cast<uint32>( positions.size() );
		triangles.indexBuffer = indexBuffer;
		triangles.indexFormat = nvrhi::Format::R32_UINT;
		triangles.indexCount = static_cast<uint32>( indices.size() );
		nvrhi::rt::GeometryDesc geometry;
		geometry.setTriangles( triangles ).setFlags( nvrhi::rt::GeometryFlags::Opaque );
		nvrhi::rt::AccelStructDesc blasDesc;
		blasDesc.addBottomLevelGeometry( geometry ).setDebugName( "RT diagnostic BLAS" );
		blasDesc.buildFlags = nvrhi::rt::AccelStructBuildFlags::PreferFastTrace;
		blas = device->createAccelStruct( blasDesc );
		nvrhi::rt::AccelStructDesc tlasDesc;
		tlasDesc.setTopLevelMaxInstances( gameplay ? 2 : instances.size() ).setDebugName( "RT diagnostic TLAS" );
		tlasDesc.buildFlags = nvrhi::rt::AccelStructBuildFlags::AllowUpdate;
		tlas = device->createAccelStruct( tlasDesc );
		if( !blas || !tlas ) { return false; }
		for( auto& instance : instances ) { instance.setBLAS( blas ); }

		nvrhi::BindingLayoutDesc layoutDesc;
		layoutDesc.visibility = nvrhi::ShaderType::Compute;
		layoutDesc.bindings = {
			nvrhi::BindingLayoutItem::RayTracingAccelStruct( 0 ),
			nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 1 ),
			nvrhi::BindingLayoutItem::StructuredBuffer_UAV( 0 )
		};
		layout = device->createBindingLayout( layoutDesc );
		if( !layout ) { return false; }
		nvrhi::ComputePipelineDesc pipelineDesc;
		pipelineDesc.CS = shader;
		pipelineDesc.bindingLayouts = { layout };
		pipeline = device->createComputePipeline( pipelineDesc );
		if( !pipeline ) { return false; }

		// This scene can initialize while the renderer's immediate list is open.
		nvrhi::CommandListParameters listParams;
		listParams.enableImmediateExecution = false;
		nvrhi::CommandListHandle list = device->createCommandList( listParams );
		nvrhi::TimerQueryHandle timer = device->createTimerQuery();
		if( !list || !timer ) { return false; }
		list->open();
		list->writeBuffer( vertices, positions.data(), positions.size() * sizeof( idVec3 ) );
		list->writeBuffer( indexBuffer, indices.data(), indices.size() * sizeof( uint32 ) );
		list->beginTimerQuery( timer );
		list->buildBottomLevelAccelStruct( blas, &geometry, 1, blasDesc.buildFlags );
		list->buildTopLevelAccelStruct( tlas, instances.data(), instances.size(), tlasDesc.buildFlags );
		list->endTimerQuery( timer );
		list->close();
		device->executeCommandList( list );
		if( !device->waitForIdle() ) { return false; }
		const uint64 asBytes = device->getAccelStructMemoryRequirements( blas ).size +
			device->getAccelStructMemoryRequirements( tlas ).size;
		common->Printf( "RT_BUILD vertices=%u triangles=%u instances=%u asBytes=%llu gpuMs=%.6f\n",
			static_cast<uint32>( positions.size() ), static_cast<uint32>( indices.size() / 3 ),
			static_cast<uint32>( instances.size() ), static_cast<unsigned long long>( asBytes ),
			device->getTimerQueryTime( timer ) * 1000.0 );
		return true;
	}

	bool UpdateInstances( std::vector<nvrhi::rt::InstanceDesc>& instances )
	{
		for( auto& instance : instances ) { instance.setBLAS( blas ); }
		nvrhi::CommandListHandle list = device->createCommandList();
		if( !list ) { return false; }
		list->open();
		list->buildTopLevelAccelStruct( tlas, instances.data(), instances.size(),
			nvrhi::rt::AccelStructBuildFlags::AllowUpdate | nvrhi::rt::AccelStructBuildFlags::PerformUpdate );
		list->close();
		device->executeCommandList( list );
		return device->waitForIdle();
	}

	bool UpdateDynamic( nvrhi::ICommandList* list, const viewDef_t* view, bool shadowsOnly,
		std::vector<idVec4>* uv = nullptr, std::vector<const rayDynamicSurface_t*>* accepted = nullptr, uint32 firstMaterial = 0 )
	{
		if( !dynamicEnabled ) { return true; }
		std::vector<idVec3> points;
		std::vector<uint32> elements;
		uint32 count = 0, skinned = 0, skipped = 0;
		if( uv ) { uv->clear(); }
		if( accepted ) { accepted->clear(); }
		if( r_rayTracingDynamicGeometry.GetBool() )
		{
			for( const viewEntity_t* entity = view->viewEntitys; entity; entity = entity->next )
			{
				for( const rayDynamicSurface_t* surface = entity->raySurfaces; surface; surface = surface->next )
				{
					if( ( shadowsOnly && !surface->castsShadow ) || ( surface->skinned && !r_rayTracingSkinnedGeometry.GetBool() ) ) { continue; }
					if( count >= RT_DYNAMIC_SURFACES || points.size() + surface->numVerts > RT_DYNAMIC_VERTICES || elements.size() + surface->numIndexes > RT_DYNAMIC_INDICES ) { skipped++; continue; }
					bool valid = true;
					for( int v = 0; v < surface->numVerts; v++ ) { for( int c = 0; c < 3; c++ ) { valid &= std::isfinite( surface->positions[v][c] ); } }
					if( !valid ) { skipped++; continue; }
					const uint32 offset = staticVertexCount + points.size();
					points.insert( points.end(), surface->positions, surface->positions + surface->numVerts );
					for( int i = 0; i < surface->numIndexes; i++ ) { elements.push_back( offset + surface->indices[i] ); }
					if( uv ) { for( int v = 0; v < surface->numVerts; v++ ) { const idVec2& st = surface->texcoords[v]; uv->push_back( idVec4( st.x, st.y, firstMaterial + count, 0 ) ); } }
					if( accepted ) { accepted->push_back( surface ); }
					skinned += surface->skinned ? 1 : 0; count++;
				}
			}
		}
		dynamicSurfaceCount = count; dynamicTriangleCount = elements.size() / 3; dynamicSkinnedCount = skinned; dynamicSkippedCount = skipped;
		if( elements.empty() && !hadDynamic ) { return true; }
		std::vector<nvrhi::rt::InstanceDesc> instances( elements.empty() ? 1 : 2 );
		instances[0].setBLAS( blas ).setInstanceID( 0 ).setInstanceMask( 255 ).setFlags( nvrhi::rt::InstanceFlags::TriangleCullDisable );
		if( !elements.empty() )
		{
			nvrhi::rt::GeometryTriangles triangles;
			triangles.vertexBuffer = vertices; triangles.vertexFormat = nvrhi::Format::RGB32_FLOAT;
			triangles.vertexStride = sizeof( idVec3 ); triangles.vertexCount = staticVertexCount + RT_DYNAMIC_VERTICES;
			triangles.indexBuffer = indexBuffer; triangles.indexFormat = nvrhi::Format::R32_UINT;
			triangles.indexOffset = staticIndexCount * sizeof( uint32 ); triangles.indexCount = RT_DYNAMIC_INDICES;
			nvrhi::rt::GeometryDesc geometry;
			geometry.setTriangles( triangles ).setFlags( nvrhi::rt::GeometryFlags::Opaque );
			if( !dynamicBLAS )
			{
				nvrhi::rt::AccelStructDesc desc;
				desc.addBottomLevelGeometry( geometry ).setDebugName( "Frame-visible dynamic ray geometry" );
				desc.buildFlags = nvrhi::rt::AccelStructBuildFlags::PreferFastBuild;
				dynamicBLAS = device->createAccelStruct( desc );
				if( !dynamicBLAS ) { return false; }
			}
			triangles.vertexCount = staticVertexCount + points.size(); triangles.indexCount = elements.size();
			geometry.setTriangles( triangles );
			list->writeBuffer( vertices, points.data(), points.size() * sizeof( idVec3 ), staticVertexCount * sizeof( idVec3 ) );
			list->writeBuffer( indexBuffer, elements.data(), elements.size() * sizeof( uint32 ), staticIndexCount * sizeof( uint32 ) );
			list->buildBottomLevelAccelStruct( dynamicBLAS, &geometry, 1, nvrhi::rt::AccelStructBuildFlags::PreferFastBuild );
			instances[1].setBLAS( dynamicBLAS ).setInstanceID( staticIndexCount / 3 ).setInstanceMask( 255 ).setFlags( nvrhi::rt::InstanceFlags::TriangleCullDisable );
		}
		list->buildTopLevelAccelStruct( tlas, instances.data(), instances.size(), nvrhi::rt::AccelStructBuildFlags::AllowUpdate );
		hadDynamic = !elements.empty();
		return true;
	}
	uint32 StaticVertexCount() const { return staticVertexCount; }

	bool Trace( const std::vector<rtRay_t>& rays, std::vector<rtHit_t>& hits )
	{
		nvrhi::BufferDesc inputDesc;
		inputDesc.byteSize = rays.size() * sizeof( rtRay_t );
		inputDesc.structStride = sizeof( rtRay_t );
		inputDesc.initialState = nvrhi::ResourceStates::CopyDest;
		inputDesc.keepInitialState = true;
		inputDesc.debugName = "RT diagnostic rays";
		nvrhi::BufferHandle inputs = device->createBuffer( inputDesc );
		nvrhi::BufferDesc outputDesc;
		outputDesc.byteSize = rays.size() * sizeof( rtHit_t );
		outputDesc.structStride = sizeof( rtHit_t );
		outputDesc.canHaveUAVs = true;
		outputDesc.initialState = nvrhi::ResourceStates::UnorderedAccess;
		outputDesc.keepInitialState = true;
		outputDesc.debugName = "RT diagnostic results";
		nvrhi::BufferHandle outputs = device->createBuffer( outputDesc );
		nvrhi::BufferDesc readbackDesc;
		readbackDesc.byteSize = outputDesc.byteSize;
		readbackDesc.cpuAccess = nvrhi::CpuAccessMode::Read;
		readbackDesc.initialState = nvrhi::ResourceStates::CopyDest;
		readbackDesc.keepInitialState = true;
		readbackDesc.debugName = "RT diagnostic readback";
		nvrhi::BufferHandle readback = device->createBuffer( readbackDesc );
		if( !inputs || !outputs || !readback ) { return false; }
		nvrhi::BindingSetDesc bindings;
		bindings.bindings = {
			nvrhi::BindingSetItem::RayTracingAccelStruct( 0, tlas ),
			nvrhi::BindingSetItem::StructuredBuffer_SRV( 1, inputs ),
			nvrhi::BindingSetItem::StructuredBuffer_UAV( 0, outputs )
		};
		nvrhi::BindingSetHandle bindingSet = device->createBindingSet( bindings, layout );
		nvrhi::CommandListHandle list = device->createCommandList();
		nvrhi::TimerQueryHandle timer = device->createTimerQuery();
		if( !bindingSet || !list || !timer ) { return false; }
		list->open();
		list->writeBuffer( inputs, rays.data(), inputDesc.byteSize );
		nvrhi::ComputeState state;
		state.pipeline = pipeline;
		state.bindings = { bindingSet };
		list->setComputeState( state );
		list->beginTimerQuery( timer );
		list->dispatch( static_cast<uint32>( ( rays.size() + 63 ) / 64 ), 1, 1 );
		list->endTimerQuery( timer );
		list->copyBuffer( readback, 0, outputs, 0, outputDesc.byteSize );
		list->close();
		device->executeCommandList( list );
		if( !device->waitForIdle() ) { return false; }
		const void* data = device->mapBuffer( readback, nvrhi::CpuAccessMode::Read );
		if( !data ) { return false; }
		hits.resize( rays.size() );
		memcpy( hits.data(), data, outputDesc.byteSize );
		device->unmapBuffer( readback );
		common->Printf( "RT_TRACE rays=%u gpuMs=%.6f\n", static_cast<uint32>( rays.size() ),
			device->getTimerQueryTime( timer ) * 1000.0 );
		return true;
	}

public:
	nvrhi::rt::IAccelStruct* Scene() const { return tlas; }
	nvrhi::IBuffer* Positions() const { return vertices; }
	nvrhi::IBuffer* Indices() const { return indexBuffer; }

private:
	nvrhi::IDevice* device;
	nvrhi::BufferHandle vertices, indexBuffer;
	nvrhi::rt::AccelStructHandle blas, tlas, dynamicBLAS;
	uint32 staticVertexCount = 0, staticIndexCount = 0;
	bool dynamicEnabled = false, hadDynamic = false;
	nvrhi::ShaderHandle shader;
	nvrhi::BindingLayoutHandle layout;
	nvrhi::ComputePipelineHandle pipeline;
};

static bool CheckHit( const rtHit_t& hit, uint32 instance, float distance, float tolerance )
{
	const bool expectedHit = distance >= 0;
	return hit.hit == ( expectedHit ? 1u : 0u ) &&
		( !expectedHit || ( hit.instance == instance && std::isfinite( hit.distance ) &&
			std::fabs( hit.distance - distance ) <= tolerance ) );
}

static void TestSynthetic()
{
	nvrhi::IDevice* device = DiagnosticDevice( "RT_TEST" );
	if( !device ) { return; }
	std::vector<idVec3> positions = { idVec3( -1, -1, 0 ), idVec3( 1, -1, 0 ), idVec3( 0, 1, 0 ) };
	std::vector<uint32> indices = { 0, 1, 2 };
	std::vector<nvrhi::rt::InstanceDesc> instances( 4 );
	for( int i = 0; i < 4; i++ )
	{
		instances[i].setInstanceID( 17 + i ).setInstanceMask( 1u << i )
			.setFlags( nvrhi::rt::InstanceFlags::TriangleCullDisable );
	}
	instances[0].transform[11] = 2;
	instances[1].transform[3] = 3; instances[1].transform[11] = 4;
	instances[2].transform[11] = 5;
	// Rotate the fourth triangle 90 degrees about Y, then translate along X.
	const nvrhi::rt::AffineTransform rotated = { 0, 0, 1, 6, 0, 1, 0, 0, -1, 0, 0, 0 };
	instances[3].setTransform( rotated );

	std::vector<rtRay_t> rays = {
		MakeRay( idVec3( 0, 0, -1 ), idVec3( 0, 0, 1 ), 1 ),
		MakeRay( idVec3( 0, 0, -1 ), idVec3( 0, 0, 1 ), 2 ),
		MakeRay( idVec3( 3, 0, -1 ), idVec3( 0, 0, 1 ), 2 ),
		MakeRay( idVec3( 0, 0, 3 ), idVec3( 0, 0, -1 ), 1 ),
		MakeRay( idVec3( 0, 0, -1 ), idVec3( 0, 0, 1 ), 1, 0.01f, 2 ),
		MakeRay( idVec3( 0, 0, -1 ), idVec3( 0, 0, 1 ), 1, 3.5f, 4 ),
		MakeRay( idVec3( 10, 0, -1 ), idVec3( 0, 0, 1 ) ),
		MakeRay( idVec3( 0, 0, -1 ), idVec3( 0, 0, 1 ), 5 ),
		MakeRay( idVec3( 0, 0, 3 ), idVec3( 0, 0, 1 ), 5 ),
		MakeRay( idVec3( 0, 0, -1 ), idVec3( 0, 0, 1 ), 0 ),
		MakeRay( idVec3( 5, 0, 0 ), idVec3( 1, 0, 0 ), 8 ),
		MakeRay( idVec3( 3, 0, 10 ), idVec3( 0, 0, -1 ), 2 )
	};
	const float initialDistance[] = { 3, -1, 5, 1, -1, -1, -1, 3, 2, -1, 1, 6 };
	const uint32 initialInstance[] = { 17, 0, 18, 17, 0, 0, 0, 17, 19, 0, 20, 18 };
	RayQueryDiagnostic diagnostic( device );
	std::vector<rtHit_t> hits;
	if( !diagnostic.Initialize( positions, indices, instances ) || !diagnostic.Trace( rays, hits ) )
	{
		common->Printf( "RT_TEST status=FAIL reason=initialization-or-trace\n" );
		return;
	}
	int mismatches = 0;
	for( size_t i = 0; i < rays.size(); i++ )
	{
		if( !CheckHit( hits[i], initialInstance[i], initialDistance[i], 0.0001f ) ) { mismatches++; }
	}
	instances[0].transform[11] = 8;
	if( !diagnostic.UpdateInstances( instances ) || !diagnostic.Trace( rays, hits ) )
	{
		common->Printf( "RT_TEST status=FAIL reason=instance-update-or-trace\n" );
		return;
	}
	const float updatedDistance[] = { 9, -1, 5, -1, -1, -1, -1, 6, 2, -1, 1, 6 };
	const uint32 updatedInstance[] = { 17, 0, 18, 0, 0, 0, 0, 19, 19, 0, 20, 18 };
	for( size_t i = 0; i < rays.size(); i++ )
	{
		if( !CheckHit( hits[i], updatedInstance[i], updatedDistance[i], 0.0001f ) ) { mismatches++; }
	}
	common->Printf( "RT_TEST status=%s phases=2 rays=24 mismatches=%d\n", mismatches ? "FAIL" : "PASS", mismatches );
}

// Independent CPU triangle traversal supplies a closest-distance reference.
// A panorama samples all directions, including geometry outside the camera PVS.
static float ReferenceDistance( const rtRay_t& ray, const std::vector<idVec3>& positions, const std::vector<uint32>& indices )
{
	float closest = ray.tMax;
	bool hit = false;
	for( size_t i = 0; i < indices.size(); i += 3 )
	{
		const idVec3& a = positions[indices[i]];
		const idVec3 e1 = positions[indices[i + 1]] - a;
		const idVec3 e2 = positions[indices[i + 2]] - a;
		const idVec3 p = ray.direction.Cross( e2 );
		const float determinant = e1 * p;
		if( std::fabs( determinant ) < 0.000001f ) { continue; }
		const float inverse = 1.0f / determinant;
		const idVec3 t = ray.origin - a;
		const float u = ( t * p ) * inverse;
		if( u < 0 || u > 1 ) { continue; }
		const idVec3 q = t.Cross( e1 );
		const float v = ( ray.direction * q ) * inverse;
		if( v < 0 || u + v > 1 ) { continue; }
		const float distance = ( e2 * q ) * inverse;
		if( distance > ray.tMin && distance < closest ) { closest = distance; hit = true; }
	}
	return hit ? closest : -1;
}

static bool GatherStaticWorld( const idRenderWorldLocal* world, std::vector<idVec3>& positions, std::vector<uint32>& indices, int& models, int& surfaces, int& excluded, bool shadowCastersOnly = false,
	std::vector<idVec4>* uvMaterials = nullptr, std::vector<const idMaterial*>* materials = nullptr )
{
	for( int m = 0; m < world->localModels.Num(); m++ )
	{
		const idRenderModel* model = world->localModels[m];
		if( !model || !model->IsStaticWorldModel() ) { continue; }
		models++;
		for( int s = 0; s < model->NumSurfaces(); s++ )
		{
			const modelSurface_t* surface = model->Surface( s );
			const srfTriangles_t* tri = surface ? surface->geometry : nullptr;
			const idMaterial* material = surface ? surface->shader : nullptr;
			if( !tri || !material || !material->IsDrawn() || material->Coverage() != MC_OPAQUE ||
				material->Deform() != DFRM_NONE || material->HasSubview() || material->IsPortalSky() ||
				( shadowCastersOnly && ( !material->SurfaceCastsShadow() || material->TestMaterialFlag( MF_NOSELFSHADOW ) ) ) )
			{
				excluded++;
				continue;
			}
			if( tri->numVerts == 0 || tri->numIndexes == 0 ) { continue; }
			if( !tri->verts || !tri->indexes || tri->numVerts < 0 || tri->numIndexes < 0 || tri->numIndexes % 3 != 0 ||
				positions.size() + tri->numVerts > 2000000 || indices.size() + tri->numIndexes > 6000000 )
			{
				common->Printf( "RT_SCENE status=FAIL reason=invalid-or-oversized-geometry\n" );
				return false;
			}
			uint32 materialIndex = 0;
			if( materials )
			{
				auto found = std::find( materials->begin(), materials->end(), material );
				materialIndex = static_cast<uint32>( found - materials->begin() );
				if( found == materials->end() ) { materials->push_back( material ); }
			}
			uint32 offset = static_cast<uint32>( positions.size() );
			for( int v = 0; v < tri->numVerts; v++ )
			{
				const idVec3& point = tri->verts[v].xyz;
				if( !std::isfinite( point.x ) || !std::isfinite( point.y ) || !std::isfinite( point.z ) )
				{
					common->Printf( "RT_SCENE status=FAIL reason=nonfinite-geometry\n" );
					return false;
				}
				positions.push_back( point );
				if( uvMaterials )
				{
					const idVec2 uv = tri->verts[v].GetTexCoord();
					uvMaterials->push_back( idVec4( uv.x, uv.y, materialIndex, 0 ) );
				}
			}
			for( int j = 0; j < tri->numIndexes; j++ )
			{
				if( static_cast<uint32>( tri->indexes[j] ) >= static_cast<uint32>( tri->numVerts ) )
				{
					common->Printf( "RT_SCENE status=FAIL reason=invalid-index\n" );
					return false;
				}
				indices.push_back( offset + tri->indexes[j] );
			}
			surfaces++;
		}
	}
	if( indices.empty() )
	{
		common->Printf( "RT_SCENE status=SKIP reason=no-static-opaque-geometry\n" );
		return false;
	}
	return true;
}

static void TestDynamicScene()
{
	nvrhi::IDevice* device = DiagnosticDevice( "RT_DYNAMIC_TEST" );
	if( !device || !r_rayTracingDynamicGeometry.GetBool() ) { return; }
	RayQueryDiagnostic scene( device );
	std::vector<idVec3> points = { idVec3( -1, -1, 8 ), idVec3( 1, -1, 8 ), idVec3( 0, 1, 8 ) };
	std::vector<uint32> indices = { 0, 1, 2 };
	std::vector<nvrhi::rt::InstanceDesc> instances( 1 );
	instances[0].setInstanceID( 0 ).setInstanceMask( 255 ).setFlags( nvrhi::rt::InstanceFlags::TriangleCullDisable );
	if( !scene.Initialize( points, indices, instances, true ) ) { common->Printf( "RT_DYNAMIC_TEST status=FAIL initialize\n" ); return; }
	idVec3 moving[3] = { idVec3( -1, -1, 2 ), idVec3( 1, -1, 2 ), idVec3( 0, 1, 2 ) };
	triIndex_t movingIndices[3] = { 0, 1, 2 };
	rayDynamicSurface_t surface = {};
	surface.positions = moving; surface.indices = movingIndices; surface.numVerts = 3; surface.numIndexes = 3; surface.castsShadow = true;
	viewEntity_t entity = {}; entity.raySurfaces = &surface;
	viewDef_t view = {}; view.viewEntitys = &entity;
	std::vector<rtRay_t> rays( 1 );
	rays[0].origin = idVec3( 0, 0, 0 ); rays[0].direction = idVec3( 0, 0, 1 ); rays[0].tMin = 0.01f; rays[0].tMax = 20; rays[0].mask = 255;
	int mismatches = 0;
	for( int phase = 0; phase < 4; phase++ )
	{
		if( phase == 1 ) { for( idVec3& p : moving ) { p.z = 4; } }
		if( phase == 2 ) { surface.castsShadow = false; }
		if( phase == 3 ) { view.viewEntitys = nullptr; }
		nvrhi::CommandListParameters params; params.enableImmediateExecution = false;
		nvrhi::CommandListHandle list = device->createCommandList( params );
		list->open();
		const bool built = scene.UpdateDynamic( list, &view, phase == 2 );
		list->close(); device->executeCommandList( list );
		std::vector<rtHit_t> hits;
		if( !built || !device->waitForIdle() || !scene.Trace( rays, hits ) || !CheckHit( hits[0], phase < 2 ? 1 : 0, phase == 0 ? 2 : ( phase == 1 ? 4 : 8 ), 0.001f ) ) { mismatches++; }
	}
	common->Printf( "RT_DYNAMIC_TEST status=%s phases=4 mismatches=%d\n", mismatches == 0 ? "PASS" : "FAIL", mismatches );
}

static void TestStaticWorld()
{
	nvrhi::IDevice* device = DiagnosticDevice( "RT_SCENE" );
	if( !device ) { return; }
	if( !tr.primaryWorld || !tr.primaryView || tr.primaryView->renderWorld != tr.primaryWorld )
	{
		common->Printf( "RT_SCENE status=SKIP reason=no-world\n" );
		return;
	}
	std::vector<idVec3> positions;
	std::vector<uint32> indices;
	int models = 0, surfaces = 0, excluded = 0;
	if( !GatherStaticWorld( tr.primaryWorld, positions, indices, models, surfaces, excluded ) ) { return; }
	const int width = 512, height = 256;
	const renderView_t view = tr.primaryView->renderView;
	std::vector<rtRay_t> rays;
	rays.reserve( width * height );
	for( int y = 0; y < height; y++ )
	{
		float pitch = ( 0.5f - ( y + 0.5f ) / height ) * idMath::PI;
		for( int x = 0; x < width; x++ )
		{
			float yaw = ( ( x + 0.5f ) / width - 0.5f ) * idMath::TWO_PI;
			idVec3 direction = std::cos( pitch ) * std::cos( yaw ) * view.viewaxis[0] -
				std::cos( pitch ) * std::sin( yaw ) * view.viewaxis[1] + std::sin( pitch ) * view.viewaxis[2];
			direction.Normalize();
			rays.push_back( MakeRay( view.vieworg, direction ) );
		}
	}
	std::vector<nvrhi::rt::InstanceDesc> instances( 1 );
	instances[0].setInstanceID( 7 ).setInstanceMask( 255 ).setFlags( nvrhi::rt::InstanceFlags::TriangleCullDisable );
	RayQueryDiagnostic diagnostic( device );
	std::vector<rtHit_t> hits;
	if( !diagnostic.Initialize( positions, indices, instances ) || !diagnostic.Trace( rays, hits ) )
	{
		common->Printf( "RT_SCENE status=FAIL reason=initialization-or-trace\n" );
		return;
	}
	int mismatches = 0, hitCount = 0, behindHits = 0, invalid = 0;
	std::vector<byte> pixels( width * height * 4 );
	for( size_t i = 0; i < hits.size(); i++ )
	{
		const rtHit_t& hit = hits[i];
		if( hit.hit > 1 || ( hit.hit && ( !std::isfinite( hit.distance ) || hit.distance <= rays[i].tMin ||
			hit.distance >= rays[i].tMax || hit.instance != 7 || hit.primitive >= indices.size() / 3 ) ) )
		{
			invalid++;
		}
		int value = 0;
		if( hit.hit && std::isfinite( hit.distance ) && hit.distance > 0 )
		{
			hitCount++;
			if( rays[i].direction * view.viewaxis[0] < 0 ) { behindHits++; }
			value = idMath::ClampInt( 0, 255, static_cast<int>( 255 * ( 1 - std::log2( 1 + hit.distance ) / std::log2( 8193.0f ) ) ) );
		}
		pixels[i * 4 + 0] = pixels[i * 4 + 1] = pixels[i * 4 + 2] = static_cast<byte>( value );
		pixels[i * 4 + 3] = 255;
	}
	for( int sample = 0; sample < 32; sample++ )
	{
		size_t i = ( 997 + sample * 4051 ) % rays.size();
		float expected = ReferenceDistance( rays[i], positions, indices );
		if( !CheckHit( hits[i], 7, expected, Max( 0.05f, expected * 0.0005f ) ) ) { mismatches++; }
	}
	R_WritePNG( "screenshots/rt_static_world.png", pixels.data(), 4, width, height, "fs_savepath" );
	common->Printf( "RT_SCENE status=%s models=%d surfaces=%d excluded=%d triangles=%u rays=%u hits=%d behindHits=%d referenceRays=32 mismatches=%d invalid=%d\n",
		( mismatches || invalid || hitCount == 0 || behindHits == 0 ) ? "FAIL" : "PASS", models, surfaces, excluded,
		static_cast<uint32>( indices.size() / 3 ), static_cast<uint32>( rays.size() ), hitCount, behindHits, mismatches, invalid );
	common->Printf( "RT scene capture: screenshots/rt_static_world.png (static opaque world only; no gameplay lighting)\n" );
}
struct rtAOConstants_t
{
	idRenderMatrix clipToWorld;
	idVec4 cameraRadius;
	idVec4 viewport;
	idVec4 options;
};
static_assert( sizeof( rtAOConstants_t ) == 112, "RT AO constants must match HLSL" );

class RayTracedAO
{
public:
	explicit RayTracedAO( nvrhi::IDevice* device ) : scene( device ), device( device ) {}
	bool Initialize( const idRenderWorldLocal* world )
	{
		std::vector<idVec3> positions;
		std::vector<uint32> indices;
		int models = 0, surfaces = 0, excluded = 0;
		if( !GatherStaticWorld( world, positions, indices, models, surfaces, excluded ) ) { return false; }
		std::vector<nvrhi::rt::InstanceDesc> instances( 1 );
		instances[0].setInstanceID( 0 ).setInstanceMask( 255 ).setFlags( nvrhi::rt::InstanceFlags::TriangleCullDisable );
		if( !scene.Initialize( positions, indices, instances, true ) ) { return false; }
		void* bytes = nullptr;
		int size = fileSystem->ReadFile( "renderprogs2/dxil/rt/ambient_occlusion.cs.dxil", &bytes );
		if( size <= 0 || !bytes )
		{
			if( bytes ) { fileSystem->FreeFile( bytes ); }
			return false;
		}
		nvrhi::ShaderHandle shader = device->createShader( nvrhi::ShaderDesc( nvrhi::ShaderType::Compute ), bytes, size );
		fileSystem->FreeFile( bytes );
		if( !shader ) { return false; }
		nvrhi::BindingLayoutDesc desc;
		desc.visibility = nvrhi::ShaderType::Compute;
		desc.bindings = { nvrhi::BindingLayoutItem::VolatileConstantBuffer( 0 ),
			nvrhi::BindingLayoutItem::RayTracingAccelStruct( 0 ), nvrhi::BindingLayoutItem::Texture_SRV( 1 ),
			nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 2 ), nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 3 ),
			nvrhi::BindingLayoutItem::Texture_UAV( 0 ), nvrhi::BindingLayoutItem::StructuredBuffer_UAV( 1 ) };
		layout = device->createBindingLayout( desc );
		if( !layout ) { return false; }
		nvrhi::ComputePipelineDesc pipelineDesc;
		pipelineDesc.CS = shader;
		pipelineDesc.bindingLayouts = { layout };
		pipeline = device->createComputePipeline( pipelineDesc );
		nvrhi::BufferDesc cb;
		cb.byteSize = sizeof( rtAOConstants_t );
		cb.isConstantBuffer = true;
		cb.isVolatile = true;
		cb.maxVersions = 16;
		cb.debugName = "Ray-traced AO constants";
		constants = device->createBuffer( cb );
		nvrhi::BufferDesc counters;
		counters.byteSize = 16;
		counters.structStride = 4;
		counters.canHaveUAVs = true;
		counters.initialState = nvrhi::ResourceStates::UnorderedAccess;
		counters.keepInitialState = true;
		counters.debugName = "Ray-traced AO sampled counters";
		stats = device->createBuffer( counters );
		return pipeline && constants && stats;
	}

	bool Render( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* depth, nvrhi::ITexture* output )
	{
		if( !scene.UpdateDynamic( list, view, false ) ) { return false; }
		if( !bindingSet || boundDepth != depth || boundOutput != output )
		{
			nvrhi::BindingSetDesc desc;
			desc.bindings = { nvrhi::BindingSetItem::ConstantBuffer( 0, constants ),
				nvrhi::BindingSetItem::RayTracingAccelStruct( 0, scene.Scene() ), nvrhi::BindingSetItem::Texture_SRV( 1, depth ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 2, scene.Positions() ), nvrhi::BindingSetItem::StructuredBuffer_SRV( 3, scene.Indices() ),
				nvrhi::BindingSetItem::Texture_UAV( 0, output ), nvrhi::BindingSetItem::StructuredBuffer_UAV( 1, stats ) };
			bindingSet = device->createBindingSet( desc, layout );
			if( !bindingSet ) { return false; }
			boundDepth = depth;
			boundOutput = output;
		}
		rtAOConstants_t data;
		data.clipToWorld = view->unprojectionToWorldRenderMatrix;
		data.cameraRadius = idVec4( view->renderView.vieworg.x, view->renderView.vieworg.y, view->renderView.vieworg.z, r_rayTracedAORadius.GetFloat() );
		data.viewport = idVec4( view->viewport.x1, view->viewport.y1, view->viewport.GetWidth(), view->viewport.GetHeight() );
		data.options = idVec4( r_rayTracedAOStrength.GetFloat(), r_rayTracedAOSamples.GetInteger(), 0, 0 );
		list->writeBuffer( constants, &data, sizeof( data ) );
		list->clearBufferUInt( stats, 0 );
		nvrhi::ComputeState state;
		state.pipeline = pipeline;
		state.bindings = { bindingSet };
		list->beginMarker( "Ray-traced ambient occlusion" );
		list->setComputeState( state );
		list->dispatch( ( view->viewport.GetWidth() + 7 ) / 8, ( view->viewport.GetHeight() + 7 ) / 8, 1 );
		list->endMarker();
		frames++;
		return true;
	}

	void PrintStatus()
	{
		nvrhi::BufferDesc desc;
		desc.byteSize = 16;
		desc.cpuAccess = nvrhi::CpuAccessMode::Read;
		desc.initialState = nvrhi::ResourceStates::CopyDest;
		desc.keepInitialState = true;
		nvrhi::BufferHandle readback = device->createBuffer( desc );
		// Keep explicit status readback independent of the renderer's list.
		nvrhi::CommandListParameters listParams;
		listParams.enableImmediateExecution = false;
		nvrhi::CommandListHandle list = device->createCommandList( listParams );
		if( !readback || !list ) { return; }
		list->open();
		list->copyBuffer( readback, 0, stats, 0, 16 );
		list->close();
		device->executeCommandList( list );
		device->waitForIdle();
		const uint32* counts = static_cast<const uint32*>( device->mapBuffer( readback, nvrhi::CpuAccessMode::Read ) );
		if( !counts ) { return; }
		common->Printf( "RTAO_STATUS active=%d frames=%u samples=%u matched=%u occluded=%u\n", r_rayTracedAO.GetBool(), frames, counts[0], counts[1], counts[2] );
		device->unmapBuffer( readback );
	}

	uint32 frames = 0;
private:
	RayQueryDiagnostic scene;
	nvrhi::IDevice* device;
	nvrhi::BindingLayoutHandle layout;
	nvrhi::ComputePipelineHandle pipeline;
	nvrhi::BufferHandle constants, stats;
	nvrhi::BindingSetHandle bindingSet;
	nvrhi::TextureHandle boundDepth, boundOutput;
};

struct rtContactConstants_t
{
	idRenderMatrix clipToWorld;
	idVec4 cameraRadius, viewport, lightStrength, rectangle;
};
static_assert( sizeof( rtContactConstants_t ) == 128, "RT contact constants must match HLSL" );

class RayTracedContacts
{
public:
	explicit RayTracedContacts( nvrhi::IDevice* device ) : scene( device ), device( device ) {}
	bool Initialize( const idRenderWorldLocal* world )
	{
		std::vector<idVec3> positions;
		std::vector<uint32> indices;
		int models = 0, surfaces = 0, excluded = 0;
		if( !GatherStaticWorld( world, positions, indices, models, surfaces, excluded, true ) ) { return false; }
		std::vector<nvrhi::rt::InstanceDesc> instances( 1 );
		instances[0].setInstanceID( 0 ).setInstanceMask( 255 ).setFlags( nvrhi::rt::InstanceFlags::TriangleCullDisable );
		if( !scene.Initialize( positions, indices, instances, true ) ) { return false; }
		void* bytes = nullptr;
		int size = fileSystem->ReadFile( "renderprogs2/dxil/rt/contact_shadows.cs.dxil", &bytes );
		if( size <= 0 || !bytes )
		{
			if( bytes ) { fileSystem->FreeFile( bytes ); }
			return false;
		}
		nvrhi::ShaderHandle shader = device->createShader( nvrhi::ShaderDesc( nvrhi::ShaderType::Compute ), bytes, size );
		fileSystem->FreeFile( bytes );
		if( !shader ) { return false; }
		nvrhi::BindingLayoutDesc desc;
		desc.visibility = nvrhi::ShaderType::Compute;
		desc.bindings = { nvrhi::BindingLayoutItem::VolatileConstantBuffer( 0 ),
			nvrhi::BindingLayoutItem::RayTracingAccelStruct( 0 ), nvrhi::BindingLayoutItem::Texture_SRV( 1 ),
			nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 2 ), nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 3 ),
			nvrhi::BindingLayoutItem::Texture_SRV( 4 ), nvrhi::BindingLayoutItem::Texture_UAV( 0 ),
			nvrhi::BindingLayoutItem::Texture_UAV( 1 ), nvrhi::BindingLayoutItem::StructuredBuffer_UAV( 2 ) };
		layout = device->createBindingLayout( desc );
		if( !layout ) { return false; }
		nvrhi::ComputePipelineDesc pipelineDesc;
		pipelineDesc.CS = shader;
		pipelineDesc.bindingLayouts = { layout };
		pipeline = device->createComputePipeline( pipelineDesc );
		nvrhi::BufferDesc cb;
		cb.byteSize = sizeof( rtContactConstants_t );
		cb.isConstantBuffer = true;
		cb.isVolatile = true;
		cb.maxVersions = 4096;
		cb.debugName = "Ray-traced contact constants";
		constants = device->createBuffer( cb );
		nvrhi::BufferDesc counters;
		counters.byteSize = 32;
		counters.structStride = 4;
		counters.canHaveUAVs = true;
		counters.initialState = nvrhi::ResourceStates::UnorderedAccess;
		counters.keepInitialState = true;
		counters.debugName = "Ray-traced contact sampled counters";
		stats = device->createBuffer( counters );
		return pipeline && constants && stats;
	}

	bool BeginView( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* depth, nvrhi::ITexture* color )
	{
		if( !scene.UpdateDynamic( list, view, true ) ) { return false; }
		if( boundDepth != depth || boundColor != color || !bindingSet )
		{
			const auto& source = color->getDesc();
			nvrhi::TextureDesc desc;
			desc.width = source.width;
			desc.height = source.height;
			desc.format = source.format;
			desc.initialState = nvrhi::ResourceStates::ShaderResource;
			desc.keepInitialState = true;
			desc.debugName = "HDR before contact-shadow light";
			beforeLight = device->createTexture( desc );
			desc.format = nvrhi::Format::R8_UNORM;
			desc.isUAV = true;
			desc.debugName = "Contact-shadow visibility";
			visibility = device->createTexture( desc );
			if( !beforeLight || !visibility ) { return false; }
			nvrhi::BindingSetDesc bindings;
			bindings.bindings = { nvrhi::BindingSetItem::ConstantBuffer( 0, constants ),
				nvrhi::BindingSetItem::RayTracingAccelStruct( 0, scene.Scene() ), nvrhi::BindingSetItem::Texture_SRV( 1, depth ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 2, scene.Positions() ), nvrhi::BindingSetItem::StructuredBuffer_SRV( 3, scene.Indices() ),
				nvrhi::BindingSetItem::Texture_SRV( 4, beforeLight ), nvrhi::BindingSetItem::Texture_UAV( 0, color ),
				nvrhi::BindingSetItem::Texture_UAV( 1, visibility ), nvrhi::BindingSetItem::StructuredBuffer_UAV( 2, stats ) };
			bindingSet = device->createBindingSet( bindings, layout );
			if( !bindingSet ) { return false; }
			boundDepth = depth;
			boundColor = color;
		}
		list->clearBufferUInt( stats, 0 );
		list->clearTextureFloat( visibility, nvrhi::AllSubresources, nvrhi::Color( 1.0f ) );
		frames++;
		lights = 0;
		return true;
	}

	bool BeginLight( nvrhi::ICommandList* list, const viewDef_t* view, const viewLight_t* light )
	{
		if( light->parallel || light->shadowLOD < 0 || !light->lightShader->LightCastsShadows() ||
			( !light->localInteractions && !light->globalInteractions ) ) { return false; }
		// Frontend scissors use GL's lower-left origin; texture slices use upper-left.
		const int x0 = idMath::ClampInt( 0, boundColor->getDesc().width, view->viewport.x1 + light->scissorRect.x1 );
		const int y0 = idMath::ClampInt( 0, boundColor->getDesc().height, view->viewport.y2 - light->scissorRect.y2 );
		const int x1 = idMath::ClampInt( x0, boundColor->getDesc().width, view->viewport.x1 + light->scissorRect.x2 + 1 );
		const int y1 = idMath::ClampInt( y0, boundColor->getDesc().height, view->viewport.y2 - light->scissorRect.y1 + 1 );
		width = x1 - x0;
		height = y1 - y0;
		if( width <= 0 || height <= 0 ) { return false; }
		rtContactConstants_t data;
		data.clipToWorld = view->unprojectionToWorldRenderMatrix;
		data.cameraRadius = idVec4( view->renderView.vieworg.x, view->renderView.vieworg.y, view->renderView.vieworg.z, r_rayTracedContactDistance.GetFloat() );
		data.viewport = idVec4( view->viewport.x1, view->viewport.y1, view->viewport.GetWidth(), view->viewport.GetHeight() );
		data.lightStrength = idVec4( light->globalLightOrigin.x, light->globalLightOrigin.y, light->globalLightOrigin.z, r_rayTracedContactStrength.GetFloat() );
		data.rectangle = idVec4( x0, y0, width, height );
		list->writeBuffer( constants, &data, sizeof( data ) );
		nvrhi::TextureSlice slice;
		slice.setOrigin( x0, y0 ).setSize( width, height, 1 );
		list->copyTexture( beforeLight, slice, boundColor, slice );
		// NVRHI caches framebuffer bindings independently of the engine. A copy
		// changes texture state without invalidating that cache; force RTV rebinding.
		list->clearState();
		return true;
	}

	void EndLight( nvrhi::ICommandList* list )
	{
		nvrhi::ComputeState state;
		state.pipeline = pipeline;
		state.bindings = { bindingSet };
		list->beginMarker( "Ray-traced contact shadows" );
		list->setComputeState( state );
		list->dispatch( ( width + 7 ) / 8, ( height + 7 ) / 8, 1 );
		list->endMarker();
		lights++;
		dispatches++;
	}

	void PrintStatus()
	{
		nvrhi::BufferDesc desc;
		desc.byteSize = 32;
		desc.cpuAccess = nvrhi::CpuAccessMode::Read;
		desc.initialState = nvrhi::ResourceStates::CopyDest;
		desc.keepInitialState = true;
		nvrhi::BufferHandle readback = device->createBuffer( desc );
		nvrhi::CommandListParameters params;
		params.enableImmediateExecution = false;
		nvrhi::CommandListHandle list = device->createCommandList( params );
		if( !readback || !list ) { return; }
		list->open();
		list->copyBuffer( readback, 0, stats, 0, 32 );
		list->close();
		device->executeCommandList( list );
		device->waitForIdle();
		const uint32* counts = static_cast<const uint32*>( device->mapBuffer( readback, nvrhi::CpuAccessMode::Read ) );
		if( !counts ) { return; }
		common->Printf( "RTCONTACT_STATUS active=%d frames=%u lights=%u dispatches=%u samples=%u matched=%u hits=%u modified=%u invalid=%u\n",
			r_rayTracedContactShadows.GetBool(), frames, lights, dispatches, counts[0], counts[1], counts[2], counts[3], counts[4] );
		device->unmapBuffer( readback );
	}
	nvrhi::ITexture* Visibility() const { return visibility; }
	uint32 frames = 0;
private:
	RayQueryDiagnostic scene;
	nvrhi::IDevice* device;
	nvrhi::BindingLayoutHandle layout;
	nvrhi::ComputePipelineHandle pipeline;
	nvrhi::BufferHandle constants, stats;
	nvrhi::BindingSetHandle bindingSet;
	nvrhi::TextureHandle beforeLight, visibility, boundDepth, boundColor;
	int width = 0, height = 0;
	uint32 lights = 0, dispatches = 0;
};

// The bounce pass reuses the immutable BSP traversal contract but adds UVs,
// actual material textures and frame-local light expressions. It owns no game data.
struct rtBounceMaterial_t
{
	idVec4 diffuse, emissive, diffuseS, diffuseT, emissiveS, emissiveT;
};
struct rtBounceLight_t
{
	idVec4 originShadow, color, projectS, projectT, projectQ, falloff;
};
struct rtBounceConstants_t
{
	idRenderMatrix clipToWorld;
	idRenderMatrix worldToClip;
	idVec4 cameraRadius, viewport, options, atlasOptions;
};
static_assert( sizeof( rtBounceMaterial_t ) == 96 && sizeof( rtBounceLight_t ) == 96 && sizeof( rtBounceConstants_t ) == 192, "Bounce data must match HLSL" );

struct rtReflectionConstants_t
{
	idRenderMatrix previousWorldToClip;
	idVec4 previousCamera, options, historyOptions;
};
static_assert( sizeof( rtReflectionConstants_t ) == 112, "Reflection constants must match HLSL" );

class RayTracedLighting
{
public:
	explicit RayTracedLighting( nvrhi::IDevice* device ) : scene( device ), device( device ) {}
	bool Initialize( const idRenderWorldLocal* world, nvrhi::ICommandList* list )
	{
		std::vector<idVec3> positions;
		std::vector<uint32> indices;
		std::vector<idVec4> uvMaterials;
		int models = 0, surfaces = 0, excluded = 0;
		if( !GatherStaticWorld( world, positions, indices, models, surfaces, excluded, false, &uvMaterials, &materials ) || materials.size() > 512 ) { return false; }
		staticMaterialCount = materials.size();
		materials.resize( staticMaterialCount + RT_DYNAMIC_SURFACES, nullptr );
		std::vector<nvrhi::rt::InstanceDesc> instances( 1 );
		instances[0].setInstanceID( 0 ).setInstanceMask( 255 ).setFlags( nvrhi::rt::InstanceFlags::TriangleCullDisable );
		if( !scene.Initialize( positions, indices, instances, true ) ) { return false; }
		uvBuffer = StructuredBuffer( ( uvMaterials.size() + RT_DYNAMIC_VERTICES ) * sizeof( idVec4 ), sizeof( idVec4 ), "Bounce UV and material indices" );
		materialBuffer = StructuredBuffer( materials.size() * sizeof( rtBounceMaterial_t ), sizeof( rtBounceMaterial_t ), "Bounce materials" );
		lightBuffer = StructuredBuffer( MAX_LIGHTS * sizeof( rtBounceLight_t ), sizeof( rtBounceLight_t ), "Bounce lights" );
		stats = StructuredBuffer( 32, 4, "Bounce sampled counters", true );
		constants = ConstantBuffer( sizeof( rtBounceConstants_t ), 16, "Bounce constants" );
		atlasConstants = ConstantBuffer( sizeof( idVec4 ), 4096, "Bounce atlas constants" );
		if( !uvBuffer || !materialBuffer || !lightBuffer || !stats || !constants || !atlasConstants ) { return false; }
		list->writeBuffer( uvBuffer, uvMaterials.data(), uvMaterials.size() * sizeof( idVec4 ) );

		nvrhi::BindingLayoutDesc layout;
		layout.visibility = nvrhi::ShaderType::Compute;
		layout.bindings = { nvrhi::BindingLayoutItem::VolatileConstantBuffer( 0 ), nvrhi::BindingLayoutItem::Texture_SRV( 0 ),
			nvrhi::BindingLayoutItem::Sampler( 0 ), nvrhi::BindingLayoutItem::Texture_UAV( 0 ) };
		if( !Pipeline( "material_atlas", layout, atlasLayout, atlasPipeline ) ) { return false; }
		layout.bindings = { nvrhi::BindingLayoutItem::VolatileConstantBuffer( 0 ), nvrhi::BindingLayoutItem::RayTracingAccelStruct( 0 ),
			nvrhi::BindingLayoutItem::Texture_SRV( 1 ), nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 2 ), nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 3 ),
			nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 4 ), nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 5 ), nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 6 ),
			nvrhi::BindingLayoutItem::Texture_SRV( 7 ), nvrhi::BindingLayoutItem::Texture_SRV( 8 ), nvrhi::BindingLayoutItem::Sampler( 0 ), nvrhi::BindingLayoutItem::Sampler( 1 ),
			nvrhi::BindingLayoutItem::Texture_UAV( 0 ), nvrhi::BindingLayoutItem::StructuredBuffer_UAV( 1 ) };
		if( !Pipeline( "diffuse_bounce", layout, bounceLayout, bouncePipeline ) ) { return false; }
		layout.bindings = { nvrhi::BindingLayoutItem::VolatileConstantBuffer( 0 ), nvrhi::BindingLayoutItem::Texture_SRV( 0 ),
			nvrhi::BindingLayoutItem::Texture_SRV( 1 ), nvrhi::BindingLayoutItem::Texture_UAV( 0 ) };
		if( !Pipeline( "bounce_composite", layout, compositeLayout, compositePipeline ) ) { return false; }
		nvrhi::SamplerDesc sampler;
		sampler.setAllFilters( true ).setAllAddressModes( nvrhi::SamplerAddressMode::Wrap );
		wrapSampler = device->createSampler( sampler );
		sampler.setAllAddressModes( nvrhi::SamplerAddressMode::Clamp );
		clampSampler = device->createSampler( sampler );
		if( !wrapSampler || !clampSampler ) { return false; }
		nvrhi::TextureDesc atlasDesc;
		atlasDesc.width = atlasDesc.height = TILE_SIZE;
		atlasDesc.arraySize = materials.size() * 2 + MAX_LIGHTS * 2;
		atlasDesc.dimension = nvrhi::TextureDimension::Texture2DArray;
		atlasDesc.format = nvrhi::Format::RGBA16_FLOAT;
		atlasDesc.isUAV = true;
		atlasDesc.initialState = nvrhi::ResourceStates::ShaderResource;
		atlasDesc.keepInitialState = true;
		atlasDesc.debugName = "Ray material and light texture cache";
		atlas = device->createTexture( atlasDesc );
		if( !atlas ) { return false; }
		list->clearTextureFloat( atlas, nvrhi::AllSubresources, nvrhi::Color( 0.0f ) );
		atlasSources.resize( atlasDesc.arraySize );
		atlasBindings.resize( atlasDesc.arraySize );
		materialStages.resize( materials.size() * 2, nullptr );
		int diffuseCount = 0, emissiveCount = 0;
		for( size_t m = 0; m < staticMaterialCount; m++ )
		{
			SelectMaterialStages( m );
			diffuseCount += materialStages[m * 2] ? 1 : 0;
			emissiveCount += materialStages[m * 2 + 1] ? 1 : 0;
		}
		common->Printf( "RTGI_READY materials=%u diffuse=%d emissive=%d textureSize=%d fullResolution=1\n", static_cast<uint32>( materials.size() ), diffuseCount, emissiveCount, TILE_SIZE );
		return true;
	}

	bool BeginReflections( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* depth, nvrhi::ITexture* color )
	{
		reflectionView = nullptr;
		if( reflectionFailed ) { return false; }
		if( !reflectionPipeline && !InitializeReflections() )
		{
			reflectionFailed = true;
			common->Warning( "Ray-traced reflections unavailable; retaining native probe lighting" );
			return false;
		}
		if( captureDepth != depth || captureColor != color || !captureFramebuffer )
		{
			nvrhi::TextureDesc desc;
			desc.width = color->getDesc().width;
			desc.height = color->getDesc().height;
			desc.format = nvrhi::Format::RGBA16_FLOAT;
			desc.isRenderTarget = true;
			desc.initialState = nvrhi::ResourceStates::ShaderResource;
			desc.keepInitialState = true;
			desc.debugName = "Native probe specular for ray reflection replacement";
			probeSpecular = device->createTexture( desc );
			desc.debugName = "Native specular BRDF response and roughness";
			specularResponse = device->createTexture( desc );
			desc.debugName = "Native normal-mapped reflection direction";
			reflectionNormal = device->createTexture( desc );
			if( !probeSpecular || !specularResponse || !reflectionNormal ) { return false; }
			captureFramebuffer = device->createFramebuffer( nvrhi::FramebufferDesc().addColorAttachment( color )
				.addColorAttachment( probeSpecular ).addColorAttachment( specularResponse ).addColorAttachment( reflectionNormal ).setDepthAttachment( depth ) );
			if( !captureFramebuffer ) { return false; }
			captureDepth = depth;
			captureColor = color;
			reflectionRaw = nullptr;
		}
		globalFramebuffers.rayReflectionFBO->SetApiObject( captureFramebuffer );
		list->clearTextureFloat( probeSpecular, nvrhi::AllSubresources, nvrhi::Color( 0.0f ) );
		list->clearTextureFloat( specularResponse, nvrhi::AllSubresources, nvrhi::Color( 0.0f ) );
		list->clearTextureFloat( reflectionNormal, nvrhi::AllSubresources, nvrhi::Color( 0.0f ) );
		reflectionView = view;
		captureFrame = view->taaFrameCount;
		return true;
	}

	bool HasReflectionCapture( const viewDef_t* view ) const
	{
		return reflectionView == view && captureFrame == view->taaFrameCount;
	}

	void PrintReflectionStatus()
	{
		if( !reflectionFrames || !reflectionRaw ) { common->Printf( "RTREFLECTION_STATUS active=0 frames=0\n" ); return; }
		nvrhi::BufferDesc desc;
		desc.byteSize = 32;
		desc.cpuAccess = nvrhi::CpuAccessMode::Read;
		desc.initialState = nvrhi::ResourceStates::CopyDest;
		desc.keepInitialState = true;
		nvrhi::BufferHandle readback = device->createBuffer( desc );
		nvrhi::CommandListParameters params;
		params.enableImmediateExecution = false;
		nvrhi::CommandListHandle list = device->createCommandList( params );
		if( !readback || !list ) { return; }
		list->open();
		list->copyBuffer( readback, 0, reflectionStats, 0, 32 );
		list->close();
		device->executeCommandList( list );
		device->waitForIdle();
		const uint32* counts = static_cast<const uint32*>( device->mapBuffer( readback, nvrhi::CpuAccessMode::Read ) );
		if( !counts ) { return; }
		common->Printf( "RTREFLECTION_STATUS active=%d frames=%u width=%u height=%u fullResolution=1 samples=%u matched=%u rays=%u hits=%u modified=%u invalid=%u cached=%u emissive=%u\n",
			r_rayTracedReflections.GetBool(), reflectionFrames, reflectionRaw->getDesc().width, reflectionRaw->getDesc().height,
			counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7] );
		device->unmapBuffer( readback );
	}

	bool Render( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* depth, nvrhi::ITexture* color )
	{
		std::vector<idVec4> dynamicUV;
		std::vector<const rayDynamicSurface_t*> dynamicSurfaces;
		if( !scene.UpdateDynamic( list, view, false, &dynamicUV, &dynamicSurfaces, staticMaterialCount ) ) { return false; }
		if( !dynamicUV.empty() ) { list->writeBuffer( uvBuffer, dynamicUV.data(), dynamicUV.size() * sizeof( idVec4 ), scene.StaticVertexCount() * sizeof( idVec4 ) ); }
		for( size_t m = staticMaterialCount; m < materials.size(); m++ )
		{
			const size_t index = m - staticMaterialCount;
			materials[m] = index < dynamicSurfaces.size() ? dynamicSurfaces[index]->material : nullptr;
			SelectMaterialStages( m );
		}

		const int width = view->viewport.GetWidth(), height = view->viewport.GetHeight();
		if( boundDepth != depth || boundColor != color || !bounce || bounce->getDesc().width != width || bounce->getDesc().height != height )
		{
			nvrhi::TextureDesc desc;
			desc.width = width;
			desc.height = height;
			desc.format = nvrhi::Format::RGBA16_FLOAT;
			desc.isUAV = true;
			desc.initialState = nvrhi::ResourceStates::ShaderResource;
			desc.keepInitialState = true;
			desc.debugName = "Full-resolution material bounce radiance and receiver distance";
			bounce = device->createTexture( desc );
			desc.width = color->getDesc().width;
			desc.height = color->getDesc().height;
			desc.isUAV = false;
			desc.debugName = "Material radiance before ray-traced bounce";
			surfaceRadiance = device->createTexture( desc );
			if( !bounce || !surfaceRadiance ) { return false; }
			nvrhi::BindingSetDesc bindings;
			bindings.bindings = { nvrhi::BindingSetItem::ConstantBuffer( 0, constants ), nvrhi::BindingSetItem::RayTracingAccelStruct( 0, scene.Scene() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, depth ), nvrhi::BindingSetItem::StructuredBuffer_SRV( 2, scene.Positions() ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 3, scene.Indices() ), nvrhi::BindingSetItem::StructuredBuffer_SRV( 4, uvBuffer ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 5, materialBuffer ), nvrhi::BindingSetItem::StructuredBuffer_SRV( 6, lightBuffer ),
				nvrhi::BindingSetItem::Texture_SRV( 7, atlas ), nvrhi::BindingSetItem::Texture_SRV( 8, surfaceRadiance ), nvrhi::BindingSetItem::Sampler( 0, wrapSampler ), nvrhi::BindingSetItem::Sampler( 1, clampSampler ),
				nvrhi::BindingSetItem::Texture_UAV( 0, bounce ), nvrhi::BindingSetItem::StructuredBuffer_UAV( 1, stats ) };
			bounceBindings = device->createBindingSet( bindings, bounceLayout );
			bindings.bindings = { nvrhi::BindingSetItem::ConstantBuffer( 0, constants ), nvrhi::BindingSetItem::Texture_SRV( 0, bounce ),
				nvrhi::BindingSetItem::Texture_SRV( 1, depth ), nvrhi::BindingSetItem::Texture_UAV( 0, color ) };
			compositeBindings = device->createBindingSet( bindings, compositeLayout );
			if( !bounceBindings || !compositeBindings ) { return false; }
			boundDepth = depth;
			boundColor = color;
			reflectionRaw = nullptr;
		}
		std::vector<rtBounceMaterial_t> data( materials.size() );
		float localParms[MAX_ENTITY_SHADER_PARMS] = { 1, 1, 1, 1 };
		for( size_t m = 0; m < materials.size(); m++ )
		{
			if( !materials[m] ) { continue; }
			// Dynamic registers are immutable frontend copies for this surface/pose.
			const rayDynamicSurface_t* dynamic = m >= staticMaterialCount ? dynamicSurfaces[m - staticMaterialCount] : nullptr;
			std::vector<float> evaluated;
			const float* regs = dynamic ? dynamic->shaderRegisters : materials[m]->ConstantRegisters();
			if( !regs )
			{
				evaluated.resize( materials[m]->GetNumRegisters() );
				materials[m]->EvaluateRegisters( evaluated.data(), localParms, view->renderView.shaderParms, view->renderView.time[0] * 0.001f, nullptr );
				regs = evaluated.data();
			}
			PrepareStage( list, materialStages[m * 2], regs, m * 2, 1, data[m].diffuse, data[m].diffuseS, data[m].diffuseT );
			PrepareStage( list, materialStages[m * 2 + 1], regs, m * 2 + 1, 2, data[m].emissive, data[m].emissiveS, data[m].emissiveT );
			// UV's third component is zero, leaving this component free for shadow policy.
			data[m].diffuseS.z = ( dynamic ? dynamic->castsShadow : ( materials[m]->SurfaceCastsShadow() && !materials[m]->TestMaterialFlag( MF_NOSELFSHADOW ) ) ) ? 1.0f : 0.0f;
		}
		list->writeBuffer( materialBuffer, data.data(), data.size() * sizeof( rtBounceMaterial_t ) );
		PrepareLights( list, view );
		rtBounceConstants_t cb;
		cb.clipToWorld = view->unprojectionToWorldRenderMatrix;
		idRenderMatrix::Inverse( cb.clipToWorld, cb.worldToClip );
		cb.cameraRadius = idVec4( view->renderView.vieworg.x, view->renderView.vieworg.y, view->renderView.vieworg.z, r_rayTracedGIRadius.GetFloat() );
		cb.viewport = idVec4( view->viewport.x1, view->viewport.y1, view->viewport.GetWidth(), view->viewport.GetHeight() );
		cb.options = idVec4( r_rayTracedGISamples.GetInteger(), r_rayTracedGIStrength.GetFloat(), r_rayTracedGIEmissive.GetFloat(), lightCount );
		cb.atlasOptions = idVec4( materials.size() * 2, r_rayTracingDebug.GetInteger(), 0, 0 );
		list->writeBuffer( constants, &cb, sizeof( cb ) );
		list->clearBufferUInt( stats, 0 );
		// Normal lighting reuses native interactions, including probes and normal
		// maps, before generic alpha, emissive, fog and screen-warp stages. The
		// shaders add supported emissives explicitly. Diagnostics retain their
		// late completed-scene snapshot. Snapshot before GI prevents feedback.
		list->copyTexture( surfaceRadiance, nvrhi::TextureSlice(), color, nvrhi::TextureSlice() );
		if( r_rayTracedGI.GetBool() )
		{
			nvrhi::ComputeState state;
			state.pipeline = bouncePipeline;
			state.bindings = { bounceBindings };
			list->beginMarker( "Ray-traced material bounce" );
			list->setComputeState( state );
			list->dispatch( ( width + 7 ) / 8, ( height + 7 ) / 8, 1 );
			state.pipeline = compositePipeline;
			state.bindings = { compositeBindings };
			list->setComputeState( state );
			list->dispatch( ( view->viewport.GetWidth() + 7 ) / 8, ( view->viewport.GetHeight() + 7 ) / 8, 1 );
			list->endMarker();
			frames++;
		}
		if( r_rayTracedReflections.GetBool() && HasReflectionCapture( view ) ) { RenderReflections( list, view, cb, depth, color ); }
		return true;
	}

	void PrintStatus()
	{
		nvrhi::BufferDesc desc;
		desc.byteSize = 32;
		desc.cpuAccess = nvrhi::CpuAccessMode::Read;
		desc.initialState = nvrhi::ResourceStates::CopyDest;
		desc.keepInitialState = true;
		nvrhi::BufferHandle readback = device->createBuffer( desc );
		nvrhi::CommandListParameters params;
		params.enableImmediateExecution = false;
		nvrhi::CommandListHandle list = device->createCommandList( params );
		if( !readback || !list ) { return; }
		list->open();
		list->copyBuffer( readback, 0, stats, 0, 32 );
		list->close();
		device->executeCommandList( list );
		device->waitForIdle();
		const uint32* counts = static_cast<const uint32*>( device->mapBuffer( readback, nvrhi::CpuAccessMode::Read ) );
		if( !counts ) { return; }
		common->Printf( "RTGI_STATUS active=%d frames=%u lights=%u samples=%u matched=%u hits=%u colored=%u modified=%u invalid=%u cached=%u emissive=%u\n",
			r_rayTracedGI.GetBool(), frames, lightCount, counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7] );
		device->unmapBuffer( readback );
	}
	uint32 frames = 0;
private:
	static const int TILE_SIZE = 256, MAX_LIGHTS = 16;
	bool InitializeReflections()
	{
		reflectionConstants = ConstantBuffer( sizeof( rtReflectionConstants_t ), 16, "Ray reflection temporal constants" );
		reflectionStats = StructuredBuffer( 32, 4, "Reflection sampled counters", true );
		if( !reflectionConstants || !reflectionStats ) { return false; }
		nvrhi::BindingLayoutDesc layout;
		layout.visibility = nvrhi::ShaderType::Compute;
		layout.bindings = { nvrhi::BindingLayoutItem::VolatileConstantBuffer( 0 ), nvrhi::BindingLayoutItem::VolatileConstantBuffer( 1 ),
			nvrhi::BindingLayoutItem::RayTracingAccelStruct( 0 ), nvrhi::BindingLayoutItem::Texture_SRV( 1 ),
			nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 2 ), nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 3 ),
			nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 4 ), nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 5 ), nvrhi::BindingLayoutItem::StructuredBuffer_SRV( 6 ),
			nvrhi::BindingLayoutItem::Texture_SRV( 7 ), nvrhi::BindingLayoutItem::Texture_SRV( 8 ), nvrhi::BindingLayoutItem::Texture_SRV( 9 ),
			nvrhi::BindingLayoutItem::Texture_SRV( 10 ), nvrhi::BindingLayoutItem::Texture_SRV( 11 ),
			nvrhi::BindingLayoutItem::Sampler( 0 ), nvrhi::BindingLayoutItem::Sampler( 1 ), nvrhi::BindingLayoutItem::Texture_UAV( 0 ),
			nvrhi::BindingLayoutItem::StructuredBuffer_UAV( 1 ), nvrhi::BindingLayoutItem::Texture_UAV( 2 ) };
		if( !Pipeline( "reflections", layout, reflectionLayout, reflectionPipeline ) ) { return false; }
		layout.bindings = { nvrhi::BindingLayoutItem::VolatileConstantBuffer( 0 ), nvrhi::BindingLayoutItem::VolatileConstantBuffer( 1 ),
			nvrhi::BindingLayoutItem::Texture_SRV( 0 ), nvrhi::BindingLayoutItem::Texture_SRV( 1 ), nvrhi::BindingLayoutItem::Texture_SRV( 2 ),
			nvrhi::BindingLayoutItem::Texture_SRV( 3 ), nvrhi::BindingLayoutItem::Texture_SRV( 4 ), nvrhi::BindingLayoutItem::Texture_UAV( 0 ) };
		if( !Pipeline( "reflection_filter", layout, reflectionFilterLayout, reflectionFilterPipeline ) ) { return false; }
		layout.bindings = { nvrhi::BindingLayoutItem::VolatileConstantBuffer( 0 ), nvrhi::BindingLayoutItem::VolatileConstantBuffer( 1 ),
			nvrhi::BindingLayoutItem::Texture_SRV( 0 ), nvrhi::BindingLayoutItem::Texture_SRV( 1 ), nvrhi::BindingLayoutItem::Texture_SRV( 2 ),
			nvrhi::BindingLayoutItem::Texture_SRV( 3 ), nvrhi::BindingLayoutItem::Texture_UAV( 0 ) };
		if( !Pipeline( "reflection_composite", layout, reflectionCompositeLayout, reflectionCompositePipeline ) ) { return false; }
		common->Printf( "RTREFLECTION_READY staticWorld=1 nativeMaterials=1 fullResolution=1 samples=%d\n", r_rayTracedReflectionSamples.GetInteger() );
		return true;
	}

	bool RenderReflections( nvrhi::ICommandList* list, const viewDef_t* view, const rtBounceConstants_t& cb, nvrhi::ITexture* depth, nvrhi::ITexture* color )
	{
		const int width = view->viewport.GetWidth(), height = view->viewport.GetHeight();
		if( !reflectionRaw || reflectionRaw->getDesc().width != width || reflectionRaw->getDesc().height != height )
		{
			lastReflectionFrame = -1;
			nvrhi::TextureDesc desc;
			desc.width = width;
			desc.height = height;
			desc.format = nvrhi::Format::RGBA16_FLOAT;
			desc.isUAV = true;
			desc.initialState = nvrhi::ResourceStates::ShaderResource;
			desc.keepInitialState = true;
			desc.debugName = "Full-resolution raw ray reflection and hit coverage";
			reflectionRaw = device->createTexture( desc );
			if( !reflectionRaw ) { return false; }
			for( int i = 0; i < 2; i++ )
			{
				desc.debugName = "Full-resolution reflection history and hit coverage";
				reflectionHistory[i] = device->createTexture( desc );
				desc.debugName = "Full-resolution reflection normal distance roughness guide";
				reflectionGuide[i] = device->createTexture( desc );
				if( !reflectionHistory[i] || !reflectionGuide[i] ) { reflectionRaw = nullptr; return false; }
				list->clearTextureFloat( reflectionHistory[i], nvrhi::AllSubresources, nvrhi::Color( 0.0f ) );
				list->clearTextureFloat( reflectionGuide[i], nvrhi::AllSubresources, nvrhi::Color( 0.0f ) );
			}
			for( int i = 0; i < 2; i++ )
			{
				nvrhi::BindingSetDesc bindings;
				bindings.bindings = { nvrhi::BindingSetItem::ConstantBuffer( 0, constants ), nvrhi::BindingSetItem::ConstantBuffer( 1, reflectionConstants ),
					nvrhi::BindingSetItem::RayTracingAccelStruct( 0, scene.Scene() ), nvrhi::BindingSetItem::Texture_SRV( 1, depth ),
					nvrhi::BindingSetItem::StructuredBuffer_SRV( 2, scene.Positions() ), nvrhi::BindingSetItem::StructuredBuffer_SRV( 3, scene.Indices() ),
					nvrhi::BindingSetItem::StructuredBuffer_SRV( 4, uvBuffer ), nvrhi::BindingSetItem::StructuredBuffer_SRV( 5, materialBuffer ),
					nvrhi::BindingSetItem::StructuredBuffer_SRV( 6, lightBuffer ), nvrhi::BindingSetItem::Texture_SRV( 7, atlas ),
					nvrhi::BindingSetItem::Texture_SRV( 8, surfaceRadiance ), nvrhi::BindingSetItem::Texture_SRV( 9, probeSpecular ),
					nvrhi::BindingSetItem::Texture_SRV( 10, specularResponse ), nvrhi::BindingSetItem::Texture_SRV( 11, reflectionNormal ),
					nvrhi::BindingSetItem::Sampler( 0, wrapSampler ), nvrhi::BindingSetItem::Sampler( 1, clampSampler ),
					nvrhi::BindingSetItem::Texture_UAV( 0, reflectionRaw ), nvrhi::BindingSetItem::StructuredBuffer_UAV( 1, reflectionStats ),
					nvrhi::BindingSetItem::Texture_UAV( 2, reflectionGuide[i] ) };
				reflectionBindings[i] = device->createBindingSet( bindings, reflectionLayout );
				bindings.bindings = { nvrhi::BindingSetItem::ConstantBuffer( 0, constants ), nvrhi::BindingSetItem::ConstantBuffer( 1, reflectionConstants ),
					nvrhi::BindingSetItem::Texture_SRV( 0, reflectionRaw ), nvrhi::BindingSetItem::Texture_SRV( 1, reflectionGuide[i] ),
					nvrhi::BindingSetItem::Texture_SRV( 2, reflectionHistory[i ^ 1] ), nvrhi::BindingSetItem::Texture_SRV( 3, reflectionGuide[i ^ 1] ),
					nvrhi::BindingSetItem::Texture_SRV( 4, depth ), nvrhi::BindingSetItem::Texture_UAV( 0, reflectionHistory[i] ) };
				reflectionFilterBindings[i] = device->createBindingSet( bindings, reflectionFilterLayout );
				bindings.bindings = { nvrhi::BindingSetItem::ConstantBuffer( 0, constants ), nvrhi::BindingSetItem::ConstantBuffer( 1, reflectionConstants ),
					nvrhi::BindingSetItem::Texture_SRV( 0, reflectionHistory[i] ), nvrhi::BindingSetItem::Texture_SRV( 1, probeSpecular ),
					nvrhi::BindingSetItem::Texture_SRV( 2, reflectionGuide[i] ), nvrhi::BindingSetItem::Texture_SRV( 3, specularResponse ), nvrhi::BindingSetItem::Texture_UAV( 0, color ) };
				reflectionCompositeBindings[i] = device->createBindingSet( bindings, reflectionCompositeLayout );
				if( !reflectionBindings[i] || !reflectionFilterBindings[i] || !reflectionCompositeBindings[i] ) { reflectionRaw = nullptr; return false; }
			}
		}
		rtReflectionConstants_t reflectionCB = {};
		const bool historyValid = dynamicSurfaceCount == 0 && lastReflectionFrame >= 0 && view->taaFrameCount == lastReflectionFrame + 1 &&
			reflectionEpoch == view->temporalHistoryEpoch && reflectionViewport == cb.viewport;
		reflectionCB.previousWorldToClip = historyValid ? previousReflectionMatrix : cb.worldToClip;
		reflectionCB.previousCamera = historyValid ? previousReflectionCamera : cb.cameraRadius;
		reflectionCB.options = idVec4( r_rayTracedReflectionSamples.GetInteger(), r_rayTracedReflectionStrength.GetFloat(),
			r_rayTracedReflectionRoughness.GetFloat(), r_rayTracedReflectionDistance.GetFloat() );
		reflectionCB.historyOptions = idVec4( historyValid ? 1 : 0, view->taaFrameCount & 0xffff, r_rayTracingDebug.GetInteger(), 0 );
		list->writeBuffer( reflectionConstants, &reflectionCB, sizeof( reflectionCB ) );
		list->clearBufferUInt( reflectionStats, 0 );
		const int index = reflectionFrames & 1;
		nvrhi::ComputeState state;
		state.pipeline = reflectionPipeline;
		state.bindings = { reflectionBindings[index] };
		list->beginMarker( "Full-resolution material ray reflections" );
		list->setComputeState( state );
		list->dispatch( ( width + 7 ) / 8, ( height + 7 ) / 8, 1 );
		state.pipeline = reflectionFilterPipeline;
		state.bindings = { reflectionFilterBindings[index] };
		list->setComputeState( state );
		list->dispatch( ( width + 7 ) / 8, ( height + 7 ) / 8, 1 );
		state.pipeline = reflectionCompositePipeline;
		state.bindings = { reflectionCompositeBindings[index] };
		list->setComputeState( state );
		list->dispatch( ( width + 7 ) / 8, ( height + 7 ) / 8, 1 );
		list->endMarker();
		previousReflectionMatrix = cb.worldToClip;
		previousReflectionCamera = cb.cameraRadius;
		reflectionViewport = cb.viewport;
		lastReflectionFrame = view->taaFrameCount;
		reflectionEpoch = view->temporalHistoryEpoch;
		reflectionFrames++;
		return true;
	}
	nvrhi::BufferHandle StructuredBuffer( size_t bytes, uint32 stride, const char* name, bool uav = false )
	{
		nvrhi::BufferDesc desc;
		desc.byteSize = bytes;
		desc.structStride = stride;
		desc.canHaveUAVs = uav;
		desc.initialState = uav ? nvrhi::ResourceStates::UnorderedAccess : nvrhi::ResourceStates::ShaderResource;
		desc.keepInitialState = true;
		desc.debugName = name;
		return device->createBuffer( desc );
	}
	nvrhi::BufferHandle ConstantBuffer( size_t bytes, uint32 versions, const char* name )
	{
		nvrhi::BufferDesc desc;
		desc.byteSize = bytes;
		desc.isConstantBuffer = desc.isVolatile = true;
		desc.maxVersions = versions;
		desc.debugName = name;
		return device->createBuffer( desc );
	}
	bool Pipeline( const char* name, const nvrhi::BindingLayoutDesc& desc, nvrhi::BindingLayoutHandle& layout, nvrhi::ComputePipelineHandle& pipeline )
	{
		void* bytes = nullptr;
		int size = fileSystem->ReadFile( va( "renderprogs2/dxil/rt/%s.cs.dxil", name ), &bytes );
		if( size <= 0 || !bytes )
		{
			if( bytes ) { fileSystem->FreeFile( bytes ); }
			return false;
		}
		nvrhi::ShaderHandle shader = device->createShader( nvrhi::ShaderDesc( nvrhi::ShaderType::Compute ), bytes, size );
		fileSystem->FreeFile( bytes );
		if( !shader ) { return false; }
		layout = device->createBindingLayout( desc );
		if( !layout ) { return false; }
		nvrhi::ComputePipelineDesc pipelineDesc;
		pipelineDesc.CS = shader;
		pipelineDesc.bindingLayouts = { layout };
		pipeline = device->createComputePipeline( pipelineDesc );
		return pipeline != nullptr;
	}
	bool CacheTexture( nvrhi::ICommandList* list, idImage* image, uint32 slice, int decode )
	{
		if( !image ) { return false; }
		if( !image->GetTextureHandle() ) { image->ActuallyLoadImage( true, list ); }
		nvrhi::TextureHandle texture = image->GetTextureHandle();
		if( !texture || texture->getDesc().dimension != nvrhi::TextureDimension::Texture2D || texture->getDesc().sampleCount != 1 ) { return false; }
		if( atlasSources[slice] == texture ) { return true; }
		nvrhi::BindingSetDesc bindings;
		bindings.bindings = { nvrhi::BindingSetItem::ConstantBuffer( 0, atlasConstants ), nvrhi::BindingSetItem::Texture_SRV( 0, texture ),
			nvrhi::BindingSetItem::Sampler( 0, wrapSampler ), nvrhi::BindingSetItem::Texture_UAV( 0, atlas ) };
		atlasBindings[slice] = device->createBindingSet( bindings, atlasLayout );
		if( !atlasBindings[slice] ) { return false; }
		const auto& desc = texture->getDesc();
		const float mip = idMath::ClampFloat( 0, desc.mipLevels - 1, std::log2( static_cast<float>( std::max( desc.width, desc.height ) ) / TILE_SIZE ) );
		idVec4 options( slice, decode, mip, TILE_SIZE );
		list->writeBuffer( atlasConstants, &options, sizeof( options ) );
		nvrhi::ComputeState state;
		state.pipeline = atlasPipeline;
		state.bindings = { atlasBindings[slice] };
		list->setComputeState( state );
		list->dispatch( TILE_SIZE / 8, TILE_SIZE / 8, 1 );
		atlasSources[slice] = texture;
		return true;
	}
	void SelectMaterialStages( size_t m )
	{
		materialStages[m * 2] = materialStages[m * 2 + 1] = nullptr;
		if( !materials[m] ) { return; }
		for( int s = 0; s < materials[m]->GetNumStages(); s++ )
		{
			const shaderStage_t* stage = materials[m]->GetStage( s );
			if( !stage->texture.image || stage->texture.cinematic || stage->texture.texgen != TG_EXPLICIT || stage->newStage || stage->vertexColor != SVC_IGNORE ) { continue; }
			if( stage->lighting == SL_DIFFUSE && !materialStages[m * 2] ) { materialStages[m * 2] = stage; }
			if( stage->lighting == SL_AMBIENT && !materials[m]->HasGui() && !materialStages[m * 2 + 1] &&
				( stage->drawStateBits & GLS_SRCBLEND_BITS ) == GLS_SRCBLEND_ONE && ( stage->drawStateBits & GLS_DSTBLEND_BITS ) == GLS_DSTBLEND_ONE ) { materialStages[m * 2 + 1] = stage; }
		}
	}
	void PrepareStage( nvrhi::ICommandList* list, const shaderStage_t* stage, const float* regs, uint32 slice, int decode, idVec4& tint, idVec4& s, idVec4& t )
	{
		tint = idVec4( 0, 0, 0, slice );
		s = idVec4( 1, 0, 0, 0 );
		t = idVec4( 0, 1, 0, 0 );
		if( !stage || !regs[stage->conditionRegister] || !CacheTexture( list, stage->texture.image, slice, decode ) ) { return; }
		for( int c = 0; c < 3; c++ ) { tint[c] = std::isfinite( regs[stage->color.registers[c]] ) ? idMath::ClampFloat( 0, 16, regs[stage->color.registers[c]] ) : 0; }
		if( stage->texture.hasMatrix )
		{
			float matrix[16];
			RB_GetShaderTextureMatrix( regs, &stage->texture, matrix );
			s = idVec4( matrix[0], matrix[4], 0, matrix[12] );
			t = idVec4( matrix[1], matrix[5], 0, matrix[13] );
		}
	}
	void PrepareLights( nvrhi::ICommandList* list, const viewDef_t* view )
	{
		struct candidate_t { const viewLight_t* light; const shaderStage_t* stage; float importance; };
		std::vector<candidate_t> candidates;
		for( const viewLight_t* light = view->viewLights; light; light = light->next )
		{
			if( light->parallel || light->lightShader->IsFogLight() || light->lightShader->IsBlendLight() || light->lightShader->IsAmbientLight() ) { continue; }
			for( int s = 0; s < light->lightShader->GetNumStages(); s++ )
			{
				const shaderStage_t* stage = light->lightShader->GetStage( s );
				if( !stage->texture.image || stage->texture.cinematic || !light->shaderRegisters[stage->conditionRegister] ) { continue; }
				float energy = 0;
				for( int c = 0; c < 3; c++ ) { energy += light->shaderRegisters[stage->color.registers[c]]; }
				const float importance = energy / ( 1 + ( light->globalLightOrigin - view->renderView.vieworg ).LengthSqr() / 16384.0f );
				if( std::isfinite( importance ) && importance > 0 ) { candidates.push_back( { light, stage, importance } ); }
			}
		}
		std::stable_sort( candidates.begin(), candidates.end(), []( const candidate_t& a, const candidate_t& b ) { return a.importance > b.importance; } );
		std::vector<rtBounceLight_t> data;
		for( const auto& candidate : candidates )
		{
			if( data.size() == MAX_LIGHTS ) { break; }
			uint32 slice = static_cast<uint32>( materials.size() * 2 + data.size() * 2 );
			const viewLight_t* light = candidate.light;
			const shaderStage_t* stage = candidate.stage;
			if( !CacheTexture( list, stage->texture.image, slice, 0 ) || !CacheTexture( list, light->falloffImage, slice + 1, 0 ) ) { continue; }
			rtBounceLight_t item;
			item.originShadow = idVec4( light->globalLightOrigin.x, light->globalLightOrigin.y, light->globalLightOrigin.z,
				!r_skipShadows.GetBool() && light->shadowLOD >= 0 && light->lightShader->LightCastsShadows() ? 1.0f : 0.0f );
			item.color = idVec4( 0 );
			for( int c = 0; c < 3; c++ ) { item.color[c] = idMath::ClampFloat( 0, 64, r_lightScale.GetFloat() * light->shaderRegisters[stage->color.registers[c]] ); }
			idPlane planes[4];
			memcpy( planes, light->lightProject, sizeof( planes ) );
			if( stage->texture.hasMatrix )
			{
				float matrix[16];
				RB_GetShaderTextureMatrix( light->shaderRegisters, &stage->texture, matrix );
				RB_BakeTextureMatrixIntoTexgen( planes, matrix );
			}
			memcpy( &item.projectS, planes, sizeof( planes ) );
			data.push_back( item );
		}
		lightCount = static_cast<uint32>( data.size() );
		if( lightCount ) { list->writeBuffer( lightBuffer, data.data(), data.size() * sizeof( rtBounceLight_t ) ); }
	}
	RayQueryDiagnostic scene;
	nvrhi::IDevice* device;
	std::vector<const idMaterial*> materials;
	uint32 staticMaterialCount = 0;
	std::vector<const shaderStage_t*> materialStages;
	std::vector<nvrhi::TextureHandle> atlasSources;
	std::vector<nvrhi::BindingSetHandle> atlasBindings;
	nvrhi::TextureHandle atlas, bounce, surfaceRadiance, boundDepth, boundColor;
	nvrhi::BufferHandle uvBuffer, materialBuffer, lightBuffer, stats, constants, atlasConstants;
	nvrhi::BindingLayoutHandle atlasLayout, bounceLayout, compositeLayout;
	nvrhi::ComputePipelineHandle atlasPipeline, bouncePipeline, compositePipeline;
	nvrhi::BindingSetHandle bounceBindings, compositeBindings;
	nvrhi::SamplerHandle wrapSampler, clampSampler;
	uint32 lightCount = 0;
	nvrhi::TextureHandle probeSpecular, specularResponse, reflectionNormal, reflectionRaw, captureDepth, captureColor;
	nvrhi::TextureHandle reflectionHistory[2], reflectionGuide[2];
	nvrhi::FramebufferHandle captureFramebuffer;
	nvrhi::BufferHandle reflectionConstants, reflectionStats;
	nvrhi::BindingLayoutHandle reflectionLayout, reflectionFilterLayout, reflectionCompositeLayout;
	nvrhi::ComputePipelineHandle reflectionPipeline, reflectionFilterPipeline, reflectionCompositePipeline;
	nvrhi::BindingSetHandle reflectionBindings[2], reflectionFilterBindings[2], reflectionCompositeBindings[2];
	const viewDef_t* reflectionView = nullptr;
	idRenderMatrix previousReflectionMatrix;
	idVec4 previousReflectionCamera, reflectionViewport;
	uint64 reflectionEpoch = 0;
	uint32 reflectionFrames = 0;
	int lastReflectionFrame = -1, captureFrame = -1;
	bool reflectionFailed = false;
};

class RayVisibilityDebug
{
public:
	bool Render( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* source, nvrhi::ITexture* color )
	{
		nvrhi::IDevice* device = deviceManager->GetDevice();
		if( !pipeline )
		{
			void* bytes = nullptr;
			int size = fileSystem->ReadFile( "renderprogs2/dxil/rt/visibility_debug.cs.dxil", &bytes );
			if( size <= 0 || !bytes )
			{
				if( bytes ) { fileSystem->FreeFile( bytes ); }
				return false;
			}
			nvrhi::ShaderHandle shader = device->createShader( nvrhi::ShaderDesc( nvrhi::ShaderType::Compute ), bytes, size );
			fileSystem->FreeFile( bytes );
			if( !shader ) { return false; }
			nvrhi::BindingLayoutDesc desc;
			desc.visibility = nvrhi::ShaderType::Compute;
			desc.bindings = { nvrhi::BindingLayoutItem::VolatileConstantBuffer( 0 ),
				nvrhi::BindingLayoutItem::Texture_SRV( 0 ), nvrhi::BindingLayoutItem::Texture_UAV( 0 ) };
			layout = device->createBindingLayout( desc );
			if( !layout ) { return false; }
			nvrhi::BufferDesc cb;
			cb.byteSize = sizeof( idVec4 );
			cb.isConstantBuffer = true;
			cb.isVolatile = true;
			cb.maxVersions = 16;
			cb.debugName = "Ray visibility debug constants";
			constants = device->createBuffer( cb );
			if( !constants ) { return false; }
			nvrhi::ComputePipelineDesc pipelineDesc;
			pipelineDesc.CS = shader;
			pipelineDesc.bindingLayouts = { layout };
			pipeline = device->createComputePipeline( pipelineDesc );
			if( !pipeline ) { return false; }
		}
		if( boundSource != source || boundColor != color || !bindingSet )
		{
			nvrhi::BindingSetDesc desc;
			desc.bindings = { nvrhi::BindingSetItem::ConstantBuffer( 0, constants ),
				nvrhi::BindingSetItem::Texture_SRV( 0, source ), nvrhi::BindingSetItem::Texture_UAV( 0, color ) };
			bindingSet = device->createBindingSet( desc, layout );
			if( !bindingSet ) { return false; }
			boundSource = source;
			boundColor = color;
		}
		idVec4 viewport( view->viewport.x1, view->viewport.y1, view->viewport.GetWidth(), view->viewport.GetHeight() );
		list->writeBuffer( constants, &viewport, sizeof( viewport ) );
		nvrhi::ComputeState state;
		state.pipeline = pipeline;
		state.bindings = { bindingSet };
		list->beginMarker( "Ray visibility debug" );
		list->setComputeState( state );
		list->dispatch( ( view->viewport.GetWidth() + 7 ) / 8, ( view->viewport.GetHeight() + 7 ) / 8, 1 );
		list->endMarker();
		return true;
	}
private:
	nvrhi::BindingLayoutHandle layout;
	nvrhi::ComputePipelineHandle pipeline;
	nvrhi::BufferHandle constants;
	nvrhi::BindingSetHandle bindingSet;
	nvrhi::TextureHandle boundSource, boundColor;
};

static RayTracedAO* rayTracedAO = nullptr;
static RayTracedContacts* rayTracedContacts = nullptr;
static RayVisibilityDebug* rayVisibilityDebug = nullptr;
static RayTracedLighting* rayTracedLighting = nullptr;
static const viewDef_t* contactView = nullptr;
static const idRenderWorldLocal* aoWorld = nullptr;
static bool aoFailed = false;
static bool contactFailed = false, debugFailed = false;
static bool giFailed = false;
} // namespace
#endif

void R_ClearRayTracedAO()
{
#if defined( USE_RAYTRACING )
	delete rayTracedAO;
	rayTracedAO = nullptr;
	delete rayTracedContacts;
	rayTracedContacts = nullptr;
	delete rayVisibilityDebug;
	rayVisibilityDebug = nullptr;
	delete rayTracedLighting;
	rayTracedLighting = nullptr;
	giFailed = false;
	contactView = nullptr;
	contactFailed = debugFailed = false;
	aoWorld = nullptr;
	aoFailed = false;
#endif
}

void R_RenderRayTracedAO( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* depth, nvrhi::ITexture* output )
{
#if defined( USE_RAYTRACING )
	if( !r_rayTracedAO.GetBool() || !view->renderWorld ) { return; }
	nvrhi::IDevice* device = deviceManager->GetDevice();
	if( device->getGraphicsAPI() != nvrhi::GraphicsAPI::D3D12 || !device->queryFeatureSupport( nvrhi::Feature::RayQuery ) ||
		!device->queryFeatureSupport( nvrhi::Feature::RayTracingAccelStruct ) ) { return; }
	if( aoWorld != view->renderWorld ) { R_ClearRayTracedAO(); aoWorld = view->renderWorld; }
	if( aoFailed ) { return; }
	if( !rayTracedAO )
	{
		rayTracedAO = new RayTracedAO( device );
		if( !rayTracedAO->Initialize( aoWorld ) )
		{
			delete rayTracedAO;
			rayTracedAO = nullptr;
			aoFailed = true;
			common->Warning( "Ray-traced AO unavailable; retaining SSAO for this map" );
			return;
		}
		common->Printf( "RTAO_READY staticWorld=1 raysPerPixel=%d radius=%.1f strength=%.2f\n", r_rayTracedAOSamples.GetInteger(), r_rayTracedAORadius.GetFloat(), r_rayTracedAOStrength.GetFloat() );
	}
	rayTracedAO->Render( list, view, depth, output );
#endif
}

void R_BeginRayTracedContacts( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* depth, nvrhi::ITexture* color )
{
#if defined( USE_RAYTRACING )
	contactView = nullptr;
	if( !r_rayTracedContactShadows.GetBool() || r_skipShadows.GetBool() || r_skipInteractions.GetBool() || !view->viewLights || !view->renderWorld || !view->viewEntitys ||
		view->isSubview || view->targetRender || ( view->renderView.rdflags & RDF_IRRADIANCE ) ||
		color->getDesc().sampleCount != 1 || !color->getDesc().isUAV ) { return; }
	nvrhi::IDevice* device = deviceManager->GetDevice();
	if( device->getGraphicsAPI() != nvrhi::GraphicsAPI::D3D12 || !device->queryFeatureSupport( nvrhi::Feature::RayQuery ) ||
		!device->queryFeatureSupport( nvrhi::Feature::RayTracingAccelStruct ) ) { return; }
	if( aoWorld != view->renderWorld ) { R_ClearRayTracedAO(); aoWorld = view->renderWorld; }
	if( contactFailed ) { return; }
	if( !rayTracedContacts )
	{
		rayTracedContacts = new RayTracedContacts( device );
		if( !rayTracedContacts->Initialize( aoWorld ) )
		{
			delete rayTracedContacts;
			rayTracedContacts = nullptr;
			contactFailed = true;
			common->Warning( "Ray-traced contact shadows unavailable; retaining raster shadows for this map" );
			return;
		}
		common->Printf( "RTCONTACT_READY staticShadowCasters=1 distance=%.1f strength=%.2f\n", r_rayTracedContactDistance.GetFloat(), r_rayTracedContactStrength.GetFloat() );
	}
	if( rayTracedContacts->BeginView( list, view, depth, color ) ) { contactView = view; }
#endif
}

bool R_BeginRayTracedContactLight( nvrhi::ICommandList* list, const viewDef_t* view, const viewLight_t* light )
{
#if defined( USE_RAYTRACING )
	return contactView == view && rayTracedContacts && rayTracedContacts->BeginLight( list, view, light );
#else
	return false;
#endif
}

void R_EndRayTracedContactLight( nvrhi::ICommandList* list )
{
#if defined( USE_RAYTRACING )
	rayTracedContacts->EndLight( list );
#endif
}

#if defined( USE_RAYTRACING )
static RayTracedLighting* PrepareRayTracedLighting( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* color )
{
	if( !view->renderWorld || !view->viewEntitys || view->isSubview || view->targetRender ||
		( view->renderView.rdflags & RDF_IRRADIANCE ) || color->getDesc().sampleCount != 1 || !color->getDesc().isUAV ) { return nullptr; }
	nvrhi::IDevice* device = deviceManager->GetDevice();
	if( device->getGraphicsAPI() != nvrhi::GraphicsAPI::D3D12 || !device->queryFeatureSupport( nvrhi::Feature::RayQuery ) ||
		!device->queryFeatureSupport( nvrhi::Feature::RayTracingAccelStruct ) ) { return nullptr; }
	if( aoWorld != view->renderWorld ) { R_ClearRayTracedAO(); aoWorld = view->renderWorld; }
	if( giFailed ) { return nullptr; }
	if( !rayTracedLighting )
	{
		rayTracedLighting = new RayTracedLighting( device );
		if( !rayTracedLighting->Initialize( aoWorld, list ) )
		{
			delete rayTracedLighting;
			rayTracedLighting = nullptr;
			giFailed = true;
			common->Warning( "Ray-traced material lighting unavailable; retaining raster lighting for this map" );
		}
	}
	return rayTracedLighting;
}
#endif

bool R_BeginRayTracedReflections( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* depth, nvrhi::ITexture* color )
{
#if defined( USE_RAYTRACING )
	if( !r_rayTracedReflections.GetBool() || ( view->renderView.rdflags & RDF_NOAMBIENT ) ) { return false; }
	RayTracedLighting* lighting = PrepareRayTracedLighting( list, view, color );
	return lighting && lighting->BeginReflections( list, view, depth, color );
#else
	return false;
#endif
}

bool R_RenderRayTracedGI( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* depth, nvrhi::ITexture* color, bool debugPass )
{
#if defined( USE_RAYTRACING )
	// Exactly one placement runs: normal lighting precedes alpha/fog; debug
	// views replace the completed scene. Reject before any allocation or work.
	if( debugPass != ( r_rayTracingDebug.GetInteger() != 0 ) ) { return false; }
	if( !r_rayTracedGI.GetBool() && !r_rayTracedReflections.GetBool() ) { return false; }
	RayTracedLighting* lighting = PrepareRayTracedLighting( list, view, color );
	if( !lighting || ( !r_rayTracedGI.GetBool() && !lighting->HasReflectionCapture( view ) ) ) { return false; }
	return lighting->Render( list, view, depth, color );
#else
	return false;
#endif
}

bool R_RenderRayTracingDebug( nvrhi::ICommandList* list, const viewDef_t* view, nvrhi::ITexture* ao, nvrhi::ITexture* color )
{
#if defined( USE_RAYTRACING )
	if( !r_rayTracingDebug.GetInteger() || debugFailed || !view->viewEntitys || view->isSubview || view->targetRender ||
		( view->renderView.rdflags & RDF_IRRADIANCE ) || color->getDesc().sampleCount != 1 || !color->getDesc().isUAV ) { return false; }
	nvrhi::ITexture* source = nullptr;
	if( r_rayTracingDebug.GetInteger() == 1 && r_rayTracedAO.GetBool() && r_useSSAO.GetBool() && r_useNewSsaoPass.GetBool() &&
		rayTracedAO && rayTracedAO->frames && !( view->renderView.rdflags & RDF_NOAMBIENT ) ) { source = ao; }
	if( r_rayTracingDebug.GetInteger() == 2 && r_rayTracedContactShadows.GetBool() && contactView == view && rayTracedContacts ) { source = rayTracedContacts->Visibility(); }
	if( !source ) { return false; }
	if( !rayVisibilityDebug ) { rayVisibilityDebug = new RayVisibilityDebug; }
	if( rayVisibilityDebug->Render( list, view, source, color ) ) { return true; }
	debugFailed = true;
	common->Warning( "Ray visibility debug unavailable; retaining scene color" );
#endif
	return false;
}

CONSOLE_COMMAND_SHIP( rayTracingContactStatus, "Report contact-shadow lights and sampled GPU coverage", NULL )
{
#if defined( USE_RAYTRACING )
	commonLocal.WaitGameThread();
	if( rayTracedContacts && rayTracedContacts->frames ) { rayTracedContacts->PrintStatus(); return; }
#endif
	common->Printf( "RTCONTACT_STATUS active=0 frames=0 lights=0 dispatches=0 samples=0 matched=0 hits=0 modified=0 invalid=0\n" );
}

CONSOLE_COMMAND_SHIP( rayTracingToggle, "Toggle AO, contact shadows, material bounce and reflections together; bindable", NULL )
{
	const bool enabled = !( r_rayTracedAO.GetBool() || r_rayTracedContactShadows.GetBool() || r_rayTracedGI.GetBool() || r_rayTracedReflections.GetBool() );
	r_rayTracedAO.SetBool( enabled );
	r_rayTracedContactShadows.SetBool( enabled );
	r_rayTracedGI.SetBool( enabled );
	r_rayTracedReflections.SetBool( enabled );
	r_rayTracingDebug.SetInteger( 0 );
	if( enabled ) { r_useSSAO.SetBool( true ); r_useNewSsaoPass.SetBool( true ); }
	cmdSystem->BufferCommandText( CMD_EXEC_APPEND, "neuralHistoryReset\n" );
	common->Printf( "Ray-traced lighting requested: %s (requires RT build and supported GPU)\n", enabled ? "ON" : "OFF" );
}

CONSOLE_COMMAND_SHIP( rayTracingDebugCycle, "Cycle shaded scene, visibility, bounce and reflection views; bindable", NULL )
{
	r_rayTracingDebug.SetInteger( ( r_rayTracingDebug.GetInteger() + 1 ) % 7 );
	cmdSystem->BufferCommandText( CMD_EXEC_APPEND, "neuralHistoryReset\n" );
	common->Printf( "Ray-tracing view %d: 0=scene, 1=AO, 2=contacts, 3=material bounce, 4=albedo, 5=reflections, 6=reflection roughness (enable the corresponding feature)\n", r_rayTracingDebug.GetInteger() );
}

CONSOLE_COMMAND_SHIP( rayTracingReflectionStatus, "Report full-resolution reflections and sampled GPU coverage", NULL )
{
#if defined( USE_RAYTRACING )
	commonLocal.WaitGameThread();
	if( rayTracedLighting ) { rayTracedLighting->PrintReflectionStatus(); return; }
#endif
	common->Printf( "RTREFLECTION_STATUS active=0 frames=0\n" );
}

CONSOLE_COMMAND_SHIP( rayTracingGIStatus, "Report material bounce lighting and sampled GPU coverage", NULL )
{
#if defined( USE_RAYTRACING )
	commonLocal.WaitGameThread();
	if( rayTracedLighting && rayTracedLighting->frames ) { rayTracedLighting->PrintStatus(); return; }
#endif
	common->Printf( "RTGI_STATUS active=0 frames=0 lights=0 samples=0 matched=0 hits=0 colored=0 modified=0 invalid=0\n" );
}

CONSOLE_COMMAND_SHIP( rayTracingAOStatus, "Report active ray-traced AO and sampled GPU coverage", NULL )
{
#if defined( USE_RAYTRACING )
	commonLocal.WaitGameThread();
	if( rayTracedAO && rayTracedAO->frames ) { rayTracedAO->PrintStatus(); return; }
#endif
	common->Printf( "RTAO_STATUS active=0 frames=0 samples=0 matched=0 occluded=0\n" );
}

CONSOLE_COMMAND_SHIP( rayTracingTest, "Run bounded native ray hit/miss and instance-update diagnostics", NULL )
{
#if defined( USE_RAYTRACING )
	TestSynthetic();
#else
	common->Printf( "RT_TEST status=SKIP reason=build-disabled\n" );
#endif
}

CONSOLE_COMMAND_SHIP( rayTracingScene, "Capture and validate static opaque world intersections in all directions", NULL )
{
#if defined( USE_RAYTRACING )
	TestStaticWorld();
#else
	common->Printf( "RT_SCENE status=SKIP reason=build-disabled\n" );
#endif
}

CONSOLE_COMMAND_SHIP( rayTracingDynamicStatus, "Report the last ray scene dynamic geometry counts", NULL )
{
#if defined( USE_RAYTRACING )
	common->Printf( "RTDYNAMIC_STATUS surfaces=%u triangles=%u skinnedSurfaces=%u budgetSkipped=%u fullResolution=1 visibleOnly=1\n", dynamicSurfaceCount.load(), dynamicTriangleCount.load(), dynamicSkinnedCount.load(), dynamicSkippedCount.load() );
#else
	common->Printf( "RTDYNAMIC_STATUS compiled=0\n" );
#endif
}

CONSOLE_COMMAND_SHIP( rayTracingDynamicTest, "Test dynamic ray insertion, movement, shadow exclusion and removal", NULL )
{
#if defined( USE_RAYTRACING )
	TestDynamicScene();
#else
	common->Printf( "RT_DYNAMIC_TEST status=SKIP reason=build-disabled\n" );
#endif
}


static void R_ToggleLightingControl( idCVar& setting, const char* label )
{
#if defined( USE_RAYTRACING )
	setting.SetBool( !setting.GetBool() );
	common->Printf( "%s: %s\n", label, setting.GetBool() ? "ON" : "OFF" );
#else
	common->Printf( "%s: unavailable in this build\n", label );
#endif
}
CONSOLE_COMMAND_SHIP( rayTracingReflectionToggle, "Toggle only material reflections", NULL ) { R_ToggleLightingControl( r_rayTracedReflections, "RTX reflections" ); }
CONSOLE_COMMAND_SHIP( rayTracingBounceToggle, "Toggle only diffuse material bounce", NULL ) { R_ToggleLightingControl( r_rayTracedGI, "RTX bounce" ); }
CONSOLE_COMMAND_SHIP( rayTracingAOToggle, "Toggle only ray-traced ambient occlusion", NULL ) { R_ToggleLightingControl( r_rayTracedAO, "RTX AO" ); }
CONSOLE_COMMAND_SHIP( rayTracingContactToggle, "Toggle only ray-traced contact shadows", NULL ) { R_ToggleLightingControl( r_rayTracedContactShadows, "RTX contacts" ); }
CONSOLE_COMMAND_SHIP( rayTracingDynamicToggle, "Toggle moving ray geometry; preserve lighting choices", NULL ) { R_ToggleLightingControl( r_rayTracingDynamicGeometry, "Moving ray geometry" ); }
CONSOLE_COMMAND_SHIP( rayTracingSkinnedToggle, "Toggle animated ray geometry; requires moving ray geometry", NULL ) { R_ToggleLightingControl( r_rayTracingSkinnedGeometry, "Animated ray geometry" ); }
CONSOLE_COMMAND_SHIP( neuralReconstructionToggle, "Cycle NR DLAA/DLSS presets, or toggle SDK-only TAA/DLAA", NULL )
{
	const bool nr = cvarSystem->GetCVarBool( "r_neuralCompatibilityEnable" );
	const int mode = nr ? 1 + R_NeuralReconstructionMode() % 4 : ( cvarSystem->GetCVarInteger( "r_neuralBackend" ) != 2 ? 1 : 0 );
	if( !R_SetNeuralReconstructionMode( mode ) )
	{
		common->Printf( "Reconstruction unchanged: DLAA/DLSS is unavailable in this launch.\n" );
		return;
	}
	const char* names[] = { "TAA (100%)", "DLAA (100%)", "DLSS Quality", "DLSS Balanced", "DLSS Performance" };
	common->Printf( "Reconstruction: %s%s\n", names[mode], nr && mode >= 2 ? " (experimental NR combination)" : "" );
}

static idCVar r_neuralKeysVersion( "r_neuralKeysVersion", "0", CVAR_ARCHIVE | CVAR_INTEGER, "safe RTX key migration version", 0, 1 );
CONSOLE_COMMAND_SHIP( neuralInstallKeys, "Install unused RTX F keys; preserve custom bindings and quicksave/load/screenshots", NULL )
{
	if( args.Argc() > 1 && r_neuralKeysVersion.GetInteger() >= 1 ) { return; }
	if( idStr::Icmp( idKeyInput::GetBinding( K_F6 ), "toggle r_rayTracedGI; neuralHistoryReset" ) == 0 ) { idKeyInput::SetBinding( K_F6, "" ); }
	// Undo only the exact old shipped conflict; never replace a custom quickload key.
	if( idStr::Icmp( idKeyInput::GetBinding( K_F9 ), "toggle r_rayTracedReflections; neuralHistoryReset" ) == 0 ) { idKeyInput::SetBinding( K_F9, "loadgame quick" ); }
	struct key_t { int key; const char* command; const char* oldCommand; };
	const key_t keys[] = {
		{ K_F1, "neuralReconstructionToggle", "" }, { K_F2, "rayTracingDynamicToggle", "" },
		{ K_F3, "rayTracingReflectionToggle", "" }, { K_F4, "rayTracingBounceToggle", "toggle r_rayTracedGI; neuralHistoryReset" },
		{ K_F7, "rayTracingAOToggle", "toggle r_rayTracedAO; neuralHistoryReset" },
		{ K_F8, "rayTracingContactToggle", "toggle r_rayTracedContactShadows; neuralHistoryReset" },
		{ K_F10, "rayTracingDebugCycle", "" }, { K_F11, "rayTracingToggle", "" }
	};
	for( const key_t& key : keys )
	{
		const char* binding = idKeyInput::GetBinding( key.key );
		if( !binding[0] || ( key.oldCommand[0] && idStr::Icmp( binding, key.oldCommand ) == 0 ) ) { idKeyInput::SetBinding( key.key, key.command ); }
	}
	r_neuralKeysVersion.SetInteger( 1 );
	common->Printf( "RTX keys installed in free slots. F1 reconstruction, F2 moving geometry, F3 reflections, F4 bounce, F7 AO, F8 contacts, F10 views, F11 all lighting. F6 reserved for external NR. Custom keys preserved.\n" );
}
