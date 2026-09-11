"""Run the real reconstruction setter against SDK availability and mode transitions.
Requires an MSVC developer shell.
"""
import pathlib
import subprocess
import tempfile

source = pathlib.Path('neo/renderer/NeuralTemporal.cpp').read_text()
setter = source[source.index('bool R_SetNeuralReconstructionMode('):source.index('const char* R_ValidateNeuralTemporalFrame(')]
shim = r'''
#include <map>
#include <string>
#include <stdexcept>
#include <iostream>
struct CVar { int value = 1; void SetInteger(int v) { value = v; } };
CVar r_neuralReconstructionMode, r_neuralNRReconstructionMode;
struct CVars {
    std::map<std::string, int> values;
    bool GetCVarBool(const char* key) { return values[key] != 0; }
    void SetCVarBool(const char* key, bool v) { values[key] = v; }
    void SetCVarInteger(const char* key, int v) { values[key] = v; }
} vars, *cvarSystem = &vars;
struct Commands { int resets = 0; void BufferCommandText(int, const char*) { resets++; } } commands, *cmdSystem = &commands;
bool supported = true;
bool R_StreamlineIsDLSSSupported() { return supported; }
const int ANTI_ALIASING_TAA = 2, CMD_EXEC_APPEND = 0;
void require(bool v) { if (!v) throw std::runtime_error("reconstruction default mismatch"); }
'''
checks = r'''
int main() {
    for (int nr : {0, 1}) for (bool sdk : {false, true}) for (int previous : {0, 1}) {
        vars.values["r_neuralCompatibilityEnable"] = nr; supported = sdk;
        for (int mode : {-1, 0, 1, 2, 3, 4, 5, 1, 4, 1}) {
            vars.values["r_rayTracingDynamicGeometry"] = previous;
            auto before = vars.values; int resets = commands.resets;
            bool accepted = sdk && mode >= nr && mode <= 4;
            require(R_SetNeuralReconstructionMode(mode) == accepted);
            if (!accepted) { require(vars.values == before && commands.resets == resets); continue; }
            require(vars.values["r_rayTracingDynamicGeometry"] == (mode == 0 ? previous : mode == 1));
            require(vars.values["r_neuralBackend"] == (mode == 0 ? 0 : mode == 1 ? 2 : 3));
            require(commands.resets == resets + 1);
        }
    }
    std::cout << "PASS: SDK/NR modes, unavailable/invalid choices, TAA preservation, DLAA restore and DLSS moving-geometry defaults\n";
}
'''
with tempfile.TemporaryDirectory(prefix='neuraldoom-reconstruction-') as tmp:
    root = pathlib.Path(tmp)
    cpp, exe = root / 'defaults.cpp', root / 'defaults.exe'
    cpp.write_text(shim + setter + checks)
    subprocess.run(['cl', '/nologo', '/EHsc', '/std:c++17', str(cpp), '/Fe:' + str(exe), '/Fo:' + str(root / 'defaults.obj')], check=True, cwd=root)
    subprocess.run([str(exe)], check=True)
