# Codex task — rigid or skinned motion-vector increment

> Historical development record. Instructions and status describe that checkpoint; use the [documentation index](../../../README.md) for current guidance.

Choose **one** increment per run: rigid objects or MD5/skinned objects. Do not combine both unless the existing architecture makes them inseparable and the justification is documented before edits.

For rigid objects:

- identify stable transform/history ownership;
- preserve previous/current model transforms;
- handle spawn, destroy, teleport, and sleep/wake behavior;
- validate a door/lift and a physics object with a static camera.

For MD5/skinned objects:

- identify the current skinning path and joint palette lifetime;
- select a previous-pose strategy with explicit memory/performance tradeoffs;
- compute current and previous skinned positions correctly;
- validate an animated character with a static camera, then with camera motion.

Do not add vendor SDK calls. Keep debug visualization and feature-off behavior working. Update the resource/convention documentation and test results.
