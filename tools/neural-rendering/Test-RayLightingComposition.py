#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify ray lighting preserves later glass/fog and counts emissives once.

Runs scalar color fixtures through the source's actual pass order and shader
expressions. No game assets, SDK, compiler or GPU are required.
"""
import argparse
from pathlib import Path
import re


def lerp(a, b, weight):
    return a * (1 - weight) + b * weight


def clamp(value, low, high):
    return min(max(value, low), high)


def expression(text, names, values):
    for original, scalar in names.items():
        text = text.replace(original, scalar)
    if "?" in text:
        condition, branches = text.split("?", 1)
        yes, no = branches.split(":", 1)
        return expression(yes if expression(condition, {}, values) else no, {}, values)
    return eval(text, {"__builtins__": {}, "lerp": lerp, "max": max,
                       "saturate": lambda value: clamp(value, 0, 1)}, values)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    renderer = (args.source_root / "neo/renderer/RenderBackend.cpp").read_text(encoding="utf-8")
    # Anchor in the primary view sequence, after the function definitions above.
    passes = renderer[renderer.index("\tDrawInteractions( _viewDef );"):]
    calls = list(re.finditer(r"R_RenderRayTracedGI\([^\n]+", passes))
    assert len(calls) == 2, "Expected normal and diagnostic lighting placements"
    glass = passes.index("processed = DrawShaderPasses(")
    fog = passes.index("FogAllLights();")
    resolve = passes.index("// resolve the screen for SSR")
    diagnostic = (args.source_root / "neo/renderer/RayTracingDiagnostic.cpp").read_text(encoding="utf-8")
    dispatch = diagnostic[diagnostic.index("bool R_RenderRayTracedGI("):]
    guard = re.search(r"if\( (debugPass[^{}]+) \) \{ return false; \}", dispatch).group(1)
    assert dispatch.index(guard) < dispatch.index("PrepareRayTracedLighting("), "Phase guard must precede allocation"
    declaration = (args.source_root / "neo/renderer/RenderCommon.h").read_text(encoding="utf-8")
    assert "bool debugPass = false" in declaration
    for debug in range(7):
        selected = [call.start() for call in calls if not expression(guard,
                    {"r_rayTracingDebug.GetInteger()": "debug"},
                    dict(debug=debug, debugPass=", true )" in call.group(0)))]
        assert len(selected) == 1, "Exactly one lighting render is allowed per view"
        if debug == 0:
            ray = selected[0]
        else:
            assert selected[0] > passes.index("DrawMotionVectors();"), "Diagnostics must replace the completed scene"
            assert selected[0] < passes.index("R_RenderRayTracingDebug("), "Visibility diagnostics must remain independent"
    assert ray < resolve, "SSR/refraction source must include completed opaque ray lighting"
    operations = sorted(((ray, "ray"), (glass, "glass"), (fog, "fog")))

    root = args.source_root / "neo/shaders/rt"
    composite = (root / "reflection_composite.cs.hlsl").read_text(encoding="utf-8")
    delta = re.search(r"float3 delta = ([^;]+);", composite).group(1)
    update = re.search(r"float4\(clamp\((scene\.rgb[^,]+),", composite).group(1)
    names = {"reflection.rgb": "reflection", "reflection.a": "coverage",
             "ProbeSpecular[pixel].rgb": "probe", "scene.rgb": "scene",
             "ReflectionOptions.y": "strength"}
    cases = 0
    for alpha in (0, 0.35, 1):
        for fog_amount in (0, 0.8, 1):
            for probe, reflected in ((8.0, 0.1), (0.1, 4.0)):
                diffuse, bounce, glass_color, fog_color = 0.4, 0.2, 0.15, 0.3
                strength, coverage = 0.65, 0.8
                values = dict(probe=probe, reflection=reflected * coverage,
                              coverage=coverage, strength=strength)
                values["delta"] = expression(delta, names, values)
                scene = diffuse + probe
                for _, operation in operations:
                    if operation == "ray":
                        values["scene"] = scene + bounce
                        scene = clamp(expression(update, names, values), 0, 65504)
                    elif operation == "glass":
                        scene = lerp(scene, glass_color, alpha)
                    else:
                        scene = lerp(scene, fog_color, fog_amount)
                # Analytic energy: replace only the covered opaque probe share,
                # then apply foreground transmission to all background lighting.
                opaque = diffuse + probe * (1 - strength * coverage) + reflected * strength * coverage + bounce
                expected = lerp(lerp(opaque, glass_color, alpha), fog_color, fog_amount)
                assert abs(scene - expected) < 1e-6, ("Glass/fog changed by late ray lighting", alpha, fog_amount, scene, expected)
                cases += 1

    bounce_shader = (root / "diffuse_bounce.cs.hlsl").read_text(encoding="utf-8")
    bounce_initial = re.search(r"float3 radiance = ([^;]+);", bounce_shader).group(1)
    bounce_emissive_scale = re.search(r"float cachedEmissionScale = ([^;]+);", bounce_shader).group(1)
    bounce_cached = re.search(r"radiance = (lerp\([^;]+);", bounce_shader).group(1)
    reflections = (root / "reflections.cs.hlsl").read_text(encoding="utf-8")
    reflection_initial = re.search(r"float3 radiance = ([^;]+);", reflections).group(1)
    reflection_emission = re.search(r"float3 cachedEmission = ([^;]+);", reflections).group(1)
    reflection_cached = re.search(r"if \(cacheWeight < 0.999\) radiance = ([^;]+);", reflections).group(1)
    names = {"hitAlbedo * Incident(hit, hitNormal)": "authored", "Options.z": "emissive_strength",
             "AtlasOptions.y": "debug"}
    for debug in (0, 3):
        for weight in (0, 0.5, 1):
            for strength in (0, 0.5, 1, 2):
                emission, native_cache = 2.0, 0.8
                values = dict(authored=0.5, cached=native_cache + (emission if debug else 0), emission=emission,
                              cacheWeight=weight, emissive_strength=strength, debug=debug)
                values["radiance"] = expression(bounce_initial, names, values)
                values["cachedEmissionScale"] = expression(bounce_emissive_scale, names, values)
                actual = expression(bounce_cached, names, values)
                # Late diagnostic cache historically retains one visible copy
                # even when its extra emissive-bounce strength is below one.
                expected = lerp(values["authored"] + emission * strength,
                                native_cache + emission * (max(strength, 1) if debug else strength), weight)
                assert abs(actual - expected) < 1e-6, ("Bounce emissive counted incorrectly", debug, weight, strength)
                values["cachedEmission"] = expression(reflection_emission, names, values)
                values["radiance"] = expression(reflection_initial, names, values)
                actual = expression(reflection_cached, names, values) if weight < 0.999 else values["radiance"]
                expected = lerp(values["authored"], native_cache, weight) + emission
                assert abs(actual - expected) < 1e-6, ("Reflection emissive counted incorrectly", debug, weight)
    print(f"PASS: {cases} glass/fog energy cases, single normal/debug dispatch, pre-SSR composition, and cached/offscreen emissive conservation")


if __name__ == "__main__":
    main()
