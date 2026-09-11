# Risk register

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../README.md) for current guidance.

| ID | Risk | Likelihood | Impact | Mitigation / proof needed |
|---|---|---:|---:|---|
| R1 | Current community Neural Rendering runtime/API changes or disappears | High | High | Make the feeder experiment disposable; build around engine-owned temporal inputs and official SDKs. |
| R2 | Existing TAA data is mistaken for true per-object motion vectors | High | High | Audit exact producers/consumers; validate rigid and skinned motion with static camera. |
| R3 | UI/viewmodel are embedded too early in scene color | Medium | High | Map pass order; create a HUD-free resource; make viewmodel policy explicit. |
| R4 | Doom 3 particles, material animation, flickering lights, and transparencies produce severe ghosting | High | High | Inventory effects; reactive/transparency masks; layer exclusions; motion tests. |
| R5 | MD5 previous-pose data increases complexity/memory and destabilizes animation | Medium | High | Implement after camera/rigid path; profile palette/history choices; add isolated tests. |
| R6 | NVRHI abstraction makes SDK-native D3D12 integration awkward | Medium | Medium | Keep one backend adapter; document resource states/queue ownership; avoid raw handles in shared code. |
| R7 | HDR/color-space placement causes incorrect neural input or output | Medium | High | Preserve linear and display-referred candidates; test SDR first; verify official contract. |
| R8 | Local retail assets accidentally enter Git or an archive | Medium | Critical | Copy missing files only; exact local excludes; pre-release archive audit. |
| R9 | Proprietary/unofficial runtime is redistributed | Medium | Critical | Never automate acquisition; local-only folder; explicit legal gate; archive scan. |
| R10 | Optional SDK breaks ordinary RBDOOM builds | Medium | High | OFF by default; null backend; CI/build gate without SDK. |
| R11 | Performance cost erases practical value even on high-end GPUs | Medium | Medium | POC before deep integration; measure frame times per phase; support DLSS SR after DLAA. |
| R12 | Neural output changes Doom 3 art direction more than desired | High | Medium | Controlled A/B captures; expose intensity/material controls only when supported; retain baseline. |
| R13 | Upstream renderer evolves during a long-lived fork | Medium | Medium | Small isolated commits, recorded upstream SHA, periodic deliberate rebases. |
| R14 | Codex makes broad speculative changes before renderer understanding | Medium | High | AGENTS phase gates; first session documentation-only; one acceptance-tested task per prompt. |
