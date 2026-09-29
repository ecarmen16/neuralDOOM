"""Exercise the renderer's actual history gate across dynamic/static frames.

Run in an MSVC developer environment; no GPU or game assets required.
"""
import pathlib
import re
import subprocess
import tempfile

source = pathlib.Path('neo/renderer/RayTracingDiagnostic.cpp').read_text()
gate = re.search(r'const bool historyValid = .*?;', source, re.S).group()
publish = re.search(r'lastReflectionFrame = view->taaFrameCount.*?(?=\n\t\treflectionEpoch)', source, re.S).group()
program = r'''
#include <cassert>
#include <iostream>
struct View { int taaFrameCount = 0, temporalHistoryEpoch = 1; } data, *view = &data;
struct Constants { int viewport = 1; } cb;
int dynamicSurfaceCount = 0, lastReflectionFrame = -1, reflectionEpoch = 1, reflectionViewport = 1;
bool frame(int number, int dynamic) {
    view->taaFrameCount = number; dynamicSurfaceCount = dynamic;
''' + gate + '\n' + publish + r'''
    reflectionEpoch = view->temporalHistoryEpoch; reflectionViewport = cb.viewport;
    return historyValid;
}
int main() {
    assert(!frame(0, 0));
    assert(frame(1, 0));
    assert(!frame(2, 1));
    assert(!frame(3, 0)); // Previous frame contained dynamic radiance.
    assert(frame(4, 0));
    assert(!frame(6, 0)); // Skipped frame.
    ++view->temporalHistoryEpoch; assert(!frame(7, 0));
    ++cb.viewport; assert(!frame(8, 0));
    assert(frame(9, 0));
    std::cout << "PASS: dynamic frames, disappearance, static convergence, skipped frames, epoch and viewport resets\n";
}
'''
with tempfile.TemporaryDirectory(prefix='neuraldoom-reflection-history-') as tmp:
    root = pathlib.Path(tmp)
    cpp, exe = root / 'history.cpp', root / 'history.exe'
    cpp.write_text(program)
    subprocess.run(['cl', '/nologo', '/EHsc', str(cpp), '/Fe:' + str(exe)], cwd=root, check=True)
    subprocess.run([str(exe)], check=True)
