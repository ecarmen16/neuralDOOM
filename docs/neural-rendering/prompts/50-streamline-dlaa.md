# Codex task — official Streamline/DLAA integration plan or increment

Begin only after ND3-210 through ND3-280 are verified and the user has explicitly approved an official SDK integration.

First re-check current official NVIDIA Streamline/DLSS documentation, release, supported features, and license. Do not use an extracted, leaked, private, or third-party-repacked SDK/runtime.

Scope one run to either:

1. a documentation-only dependency/integration design; or
2. one compile-gated implementation increment approved from that design.

Requirements:

- Build option OFF by default.
- Default build has no SDK headers/libraries/runtime requirement.
- Use the engine-owned temporal contract.
- Keep raw D3D12/SDK calls in one backend adapter.
- Begin with native-resolution DLAA before resolution scaling.
- Handle unsupported hardware and evaluate failure cleanly.
- Do not add RenoDX-specific assumptions to core rendering.
- Record exact SDK version, source, license, required redistributables, and removal path.

Run the full relevant temporal test matrix before marking native DLAA complete.
