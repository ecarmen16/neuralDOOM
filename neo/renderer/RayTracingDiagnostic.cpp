// SPDX-License-Identifier: GPL-3.0-or-later
// On-demand native ray-intersection diagnostics. Gameplay rendering is unchanged.
#include "precompiled.h"
#pragma hdrstop

#include "RenderCommon.h"
#include "../framework/Common_local.h"
#include "../sys/DeviceManager.h"
#include <cmath>
#include <vector>

extern DeviceManager* deviceManager;

#if defined( USE_RAYTRACING )

namespace
{
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

// All resources belong to this diagnostic invocation, including immutable copies
// of map vertices. The graphics queue completes before readback or destruction.
// Automatic NVRHI barriers order upload, BLAS, TLAS, tracing and readback.
class RayQueryDiagnostic
{
public:
	explicit RayQueryDiagnostic( nvrhi::IDevice* value ) : device( value ) {}

	bool Initialize( const std::vector<idVec3>& positions, const std::vector<uint32>& indices,
		std::vector<nvrhi::rt::InstanceDesc>& instances )
	{
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
		vertexDesc.byteSize = positions.size() * sizeof( idVec3 );
		vertexDesc.isAccelStructBuildInput = true;
		vertexDesc.initialState = nvrhi::ResourceStates::CopyDest;
		vertexDesc.keepInitialState = true;
		vertexDesc.debugName = "RT diagnostic positions";
		vertices = device->createBuffer( vertexDesc );
		nvrhi::BufferDesc indexDesc = vertexDesc;
		indexDesc.byteSize = indices.size() * sizeof( uint32 );
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
		tlasDesc.setTopLevelMaxInstances( instances.size() ).setDebugName( "RT diagnostic TLAS" );
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

		nvrhi::CommandListHandle list = device->createCommandList();
		nvrhi::TimerQueryHandle timer = device->createTimerQuery();
		if( !list || !timer ) { return false; }
		list->open();
		list->writeBuffer( vertices, positions.data(), vertexDesc.byteSize );
		list->writeBuffer( indexBuffer, indices.data(), indexDesc.byteSize );
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

private:
	nvrhi::IDevice* device;
	nvrhi::BufferHandle vertices, indexBuffer;
	nvrhi::rt::AccelStructHandle blas, tlas;
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
	for( int m = 0; m < tr.primaryWorld->localModels.Num(); m++ )
	{
		const idRenderModel* model = tr.primaryWorld->localModels[m];
		if( !model || !model->IsStaticWorldModel() ) { continue; }
		models++;
		for( int s = 0; s < model->NumSurfaces(); s++ )
		{
			const modelSurface_t* surface = model->Surface( s );
			const srfTriangles_t* tri = surface ? surface->geometry : nullptr;
			const idMaterial* material = surface ? surface->shader : nullptr;
			if( !tri || !material || !material->IsDrawn() || material->Coverage() != MC_OPAQUE ||
				material->Deform() != DFRM_NONE || material->IsPortalSky() )
			{
				excluded++;
				continue;
			}
			if( tri->numVerts == 0 || tri->numIndexes == 0 ) { continue; }
			if( !tri->verts || !tri->indexes || tri->numVerts < 0 || tri->numIndexes < 0 || tri->numIndexes % 3 != 0 ||
				positions.size() + tri->numVerts > 2000000 || indices.size() + tri->numIndexes > 6000000 )
			{
				common->Printf( "RT_SCENE status=FAIL reason=invalid-or-oversized-geometry\n" );
				return;
			}
			uint32 offset = static_cast<uint32>( positions.size() );
			for( int v = 0; v < tri->numVerts; v++ )
			{
				const idVec3& point = tri->verts[v].xyz;
				if( !std::isfinite( point.x ) || !std::isfinite( point.y ) || !std::isfinite( point.z ) )
				{
					common->Printf( "RT_SCENE status=FAIL reason=nonfinite-geometry\n" );
					return;
				}
				positions.push_back( point );
			}
			for( int j = 0; j < tri->numIndexes; j++ )
			{
				if( static_cast<uint32>( tri->indexes[j] ) >= static_cast<uint32>( tri->numVerts ) )
				{
					common->Printf( "RT_SCENE status=FAIL reason=invalid-index\n" );
					return;
				}
				indices.push_back( offset + tri->indexes[j] );
			}
			surfaces++;
		}
	}
	if( indices.empty() )
	{
		common->Printf( "RT_SCENE status=SKIP reason=no-static-opaque-geometry\n" );
		return;
	}
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
} // namespace
#endif

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
