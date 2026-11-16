# Species CPU timing measurement

Normal main scene, Godot 4.7.2, 1280x720 Compatibility renderer; VSync off, FPS cap 60, HUD/animals/overlay on. Two measured runs: 5 seconds warmup + 30 seconds measurement each. No script profiler attached. Source changes are confined to this output copy.

Decision is AnimalSystem.decide including behavior-tree update and intent reset. Perception is each species perceive loop. Pressure generation is measured separately. Shared grid build, dog task assignment and steering are separate stages. Decision iteration order is preserved; per-animal timers introduce small measurement overhead. Numbers are CPU elapsed time, not GPU timing.

Weighted measured steps: 1584; mean step: 37.410341 ms; perception + decision: 70.184%.

|Species|Mean alive|Perception ms/step|Pressure ms/step|Decision ms/step|Total ms/step|Perception us/animal|Decision us/animal|
|---|---:|---:|---:|---:|---:|---:|---:|
|Sheep|815.130051|4.962710|0.000000|7.640944|12.603655|6.088243|9.373896|
|Wolf|87.000000|3.016811|1.523660|1.210323|5.750794|34.675984|13.911761|
|Dog|43.000000|6.303910|0.744235|0.526595|7.574740|146.602566|12.246388|

Shared stage means (ms/step): {"Cleanup": 3.5075157828282846, "Decision": 9.692850378787876, "Interaction": 0.19063952020202032, "Movement": 0.594198863636364, "Perception": 16.563273358585853, "SpatialBuild": 4.37097095959596, "Steering": 1.9615827020201995, "TaskAssignment": 0.529309343434343}

Baseline (without species timers): 36.983729 ms/step. This is an observational comparison, not an exact timer overhead calibration.

Raw evidence:
- [species_main_r1](project/output/performance/2026-11-16T12-41-32_species_main_r1_58880_1952778/result.json): 800 steps; 37.246788 ms/step; 6.656 FPS; 148.987150 ms simulation/frame; steps/frame 4.0; frame P95 205.129000 ms; sim/wall 0.443749; counts [822, 87, 43] -> [810, 87, 43].
- [baseline_main](project/output/performance/2026-11-16T12-42-21_baseline_main_69280_2149796/result.json): 792 steps; 36.983729 ms/step; 6.578 FPS; 147.934914 ms simulation/frame; steps/frame 4.0; frame P95 214.873000 ms; sim/wall 0.438562; counts [822, 87, 43] -> [810, 87, 43].
- [species_main_r2](project/output/performance/2026-11-16T12-43-06_species_main_r2_33524_2260585/result.json): 784 steps; 37.577232 ms/step; 6.533 FPS; 150.308929 ms simulation/frame; steps/frame 4.0; frame P95 212.828000 ms; sim/wall 0.435541; counts [822, 87, 43] -> [810, 87, 43].

The existing configured_counts startup field disagrees with actual live population; this report uses observed live counts and per-step animal counts. Captures reduce sheep counts during warmup and measurement. Per-species decision sums exclude timer accumulation and loop dispatch, so they are slightly below the inclusive Decision stage. Pressure reset is included only in the overall Perception stage.

Formal repository source was not modified. The two instrumented scripts are preserved beside this report and in the project copy. All benchmark launchers exited with code 0; inspect their stderr logs for errors.
