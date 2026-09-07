include(../compileshaders.cmake)

file(GLOB globalshaders "BRDF.inc.hlsl" "global_inc.hlsl" "vulkan.hlsli" "renderParmSet0.inc.hlsl" "renderParmSet1.inc.hlsl" "renderParmSet2.inc.hlsl" "renderParmSet3.inc.hlsl" "renderParmSet4.inc.hlsl" "renderParmSet5.inc.hlsl" "renderParmSet6.inc.hlsl" "renderParmSet7.inc.hlsl" "renderParmSet8.inc.hlsl" "renderParmSet9.inc.hlsl" "renderParmSet10.inc.hlsl" "renderParmSet11.inc.hlsl" "renderParmSet12.inc.hlsl" "renderParmSet13.inc.hlsl" "renderParmSet14.inc.hlsl")
file(GLOB builtins "builtin/*.hlsl")
file(GLOB debug "builtin/debug/*hlsl")
file(GLOB fog "builtin/fog/*hlsl")
file(GLOB legacy "builtin/legacy/*hlsl")
file(GLOB lighting "builtin/lighting/*hlsl")
file(GLOB post "builtin/post/*hlsl")
file(GLOB ssao "builtin/SSAO/*hlsl")
file(GLOB ssgi "builtin/SSGI/*hlsl")
file(GLOB video "builtin/video/*hlsl")
file(GLOB vr "builtin/VR/*hlsl")
file(GLOB usershaders "*.hlsl")

list(REMOVE_ITEM usershaders ${globalshaders})

set(shaders ${globalshaders} ${builtins} ${debug} ${fog} ${legacy} ${lighting} ${post} ${ssao} ${ssgi} ${video} ${vr} ${usershaders})

source_group("builtin" FILES ${builtins})
source_group("builtin/debug" FILES ${debug})
source_group("builtin/fog" FILES ${fog})
source_group("builtin/legacy" FILES ${legacy})
source_group("builtin/lighting" FILES ${lighting})
source_group("builtin/post" FILES ${post})
source_group("builtin/SSAO" FILES ${ssao})
source_group("builtin/SSGI" FILES ${ssgi})
source_group("builtin/video" FILES ${video})
source_group("builtin/VR" FILES ${vr})
source_group("global" FILES ${globalshaders})

source_group("user" FILES ${usershaders})

if(STANDALONE)
    compile_shaders_all_platforms(
        TARGET Shaders
        CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/shaders.cfg
        OUTPUT_BASE ${CMAKE_CURRENT_SOURCE_DIR}/../../content/renderprogs2
        SHADER_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}
        SOURCES ${shaders}
    )
else()
    compile_shaders_all_platforms(
        TARGET Shaders
        CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/shaders.cfg
        OUTPUT_BASE ${CMAKE_CURRENT_SOURCE_DIR}/../../base/renderprogs2 # This path scheme is a bit odd.
        SHADER_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}
        SOURCES ${shaders}
    )
endif()

# Keep the existing SM 6.0 shader set and unsupported-hardware startup unchanged.
# Raw SM 6.5 shaders are loaded only by explicitly enabled RT features.
if(USE_RAYTRACING)
    if(NOT DXC_PATH)
        message(FATAL_ERROR "USE_RAYTRACING requires DXC with shader model 6.5 support")
    endif()
    if(STANDALONE)
        set(rt_output_root "${CMAKE_CURRENT_SOURCE_DIR}/../../content/renderprogs2")
    else()
        set(rt_output_root "${CMAKE_CURRENT_SOURCE_DIR}/../../base/renderprogs2")
    endif()
    set(rt_shaders)
    foreach(rt_name ray_query ambient_occlusion contact_shadows visibility_debug material_atlas diffuse_bounce bounce_composite)
        set(rt_shader "${rt_output_root}/dxil/rt/${rt_name}.cs.dxil")
        add_custom_command(OUTPUT "${rt_shader}"
            COMMAND ${CMAKE_COMMAND} -E make_directory "${rt_output_root}/dxil/rt"
            COMMAND "${DXC_PATH}" -T cs_6_5 -E main -WX -O3 -Zpr
                -Fo "${rt_shader}" "${CMAKE_CURRENT_SOURCE_DIR}/rt/${rt_name}.cs.hlsl"
            DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/rt/${rt_name}.cs.hlsl"
            VERBATIM)
        list(APPEND rt_shaders "${rt_shader}")
    endforeach()
    add_custom_target(RayTracingShaders DEPENDS ${rt_shaders})
endif()
