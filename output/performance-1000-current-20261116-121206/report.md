# Current 1000-animal windowed benchmark

Godot 4.7.2; fixed 2560 x 1440 arena; uniform_v1 layout; seed 1337; 870 sheep / 87 wolves / 43 dogs configured. Window 1280 x 720, GL Compatibility, vsync off, 60 FPS cap, HUD/overlay/animals on, stages sampling, script profiler off. Three serial runs, each 5 wall seconds warmup + 30 wall seconds measurement. Existing editor/background applications remained running. No source or default configuration changes.

| Run | FPS | Step mean ms | Frame P95 ms | Simulation/frame ms | Measurement start -> end counts (sheep/wolf/dog) |
|---|---:|---:|---:|---:|---|
| 1 | 6.11 | 39.85 | 206.42 | 159.40 | [821, 87, 43] -> [801, 87, 43] |
| 2 | 6.54 | 37.28 | 197.67 | 149.12 | [821, 87, 43] -> [801, 87, 43] |
| 3 | 7.19 | 33.57 | 187.45 | 134.27 | [822, 87, 43] -> [800, 87, 43] |

Median of each metric across three runs:

- average_fps: 6.5372
- frame_p95_ms: 197.6680
- step_mean_ms: 37.2797
- step_p95_ms: 44.0810
- simulation_per_frame_mean_ms: 149.1188
- simulation_per_frame_p95_ms: 193.1890
- steps_per_frame_mean: 4.0000
- simulation_wall_ratio: 0.4358
- simulation_seconds_advanced: 13.1333
- measured_wall_seconds: 30.1082
- spatial_queries_per_step: 329.6725
- spatial_candidates_per_query: 12.9323

| Stage | Median mean ms/step | Approx. share of median step |
|---|---:|---:|
| Perception | 16.261 | 43.6% |
| Decision | 12.707 | 34.1% |
| SpatialBuild | 3.869 | 10.4% |
| Cleanup | 3.507 | 9.4% |
| Movement | 0.600 | 1.6% |
| TaskAssignment | 0.585 | 1.6% |
| Interaction | 0.210 | 0.6% |

Limits: Initial population is 1000, not a constant live population; captures stay enabled. Measurement begins after warmup. Per-stage medians are independently selected and need not sum exactly to median step time. Hotspots were not separately sampled. GPU timing is unavailable. Four fixed simulation steps per rendered frame amplify the per-step CPU cost; simulation advances slower than wall time. Historical 1000-animal packed-grid figures used a 1280 x 720 arena, so they are not a controlled before/after comparison.

Evidence:
- output/performance/2026-11-16T12-09-46_current_1000_fixed_r1_69612_2953564/result.json
- output/performance/2026-11-16T12-10-30_current_1000_fixed_r2_68460_2908015/result.json
- output/performance/2026-11-16T12-11-13_current_1000_fixed_r3_70084_2917661/result.json
