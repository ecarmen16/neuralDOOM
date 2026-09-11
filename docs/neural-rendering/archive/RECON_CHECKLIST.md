# Renderer reconnaissance checklist

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../README.md) for current guidance.

Codex should cite repository-relative paths and exact symbols for each completed item.

## Build/platform

- [ ] Windows executable target and staging behavior.
- [ ] DX12 backend selection and `r_graphicsAPI` registration.
- [ ] CMake options governing NVRHI, DX12, Vulkan, shader compilation, HDR, and AA.
- [ ] Runtime DLL/search-path assumptions.

## Frame flow

- [ ] Frontend scene construction.
- [ ] Backend frame entry.
- [ ] NVRHI command-list creation/submission.
- [ ] Render-pass order.
- [ ] Post-processing order.
- [ ] Tonemapping/HDR order.
- [ ] Weapon/viewmodel order.
- [ ] GUI/HUD/menu order.
- [ ] Swapchain acquire/present.

## Resources

- [ ] Primary scene color: create site, format, size, owner, consumers.
- [ ] Pre-tonemap linear/HDR color candidate.
- [ ] Post-tonemap HUD-free candidate.
- [ ] Depth target: format, normal/reversed Z, resolves, sample count.
- [ ] Any velocity/reprojection/history textures.
- [ ] TAA history buffers and reset path.
- [ ] Resolution-scale resources.
- [ ] Exposure/luminance state.
- [ ] Transparency/particle intermediate buffers.

## Temporal state

- [ ] Current and previous camera/view/projection matrices.
- [ ] Jitter generation and application.
- [ ] Current and previous rigid model transforms.
- [ ] MD5 current pose and possible previous-pose storage.
- [ ] Spawn, teleport, camera cut, load, resize, and device-reset events.
- [ ] Whether existing TAA has real per-object motion or camera-only reprojection.

## Native D3D12 access

- [ ] `ID3D12Device` ownership/access.
- [ ] Direct queue ownership/access.
- [ ] Command-list access at proposed evaluate point.
- [ ] NVRHI texture to `ID3D12Resource` unwrapping.
- [ ] Resource-state/barrier conventions.
- [ ] Swapchain/output format and HDR state.
- [ ] Device-lost/recreation path.

## Tooling

- [ ] RenderDoc markers and capture compatibility.
- [ ] Nsight markers/capture compatibility.
- [ ] Existing screenshot/image-write utilities.
- [ ] Existing cvar/debug-view patterns.
- [ ] Existing GPU timing/profiling utilities.

## Output

- [ ] Frame-flow diagram.
- [ ] Resource table.
- [ ] Exact candidate insertion points.
- [ ] Top risks and unanswered questions.
- [ ] One narrow recommended first code task.
