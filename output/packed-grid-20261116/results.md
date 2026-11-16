# Packed Grid implementation and verification

Implemented: 60-line AGENTS, full-rebuild Packed GridService, shared sheep flock/alignment and dog protection-center statistics, source-driven wolf/dog pressure, removal of sheep FOV, configurable 30 px cells, preset version 4.
The user changed the authored arena to 2560 x 1440 during this work; that edit was preserved.

## Automated verification

- Godot 4.7.2 import/parse completed without script errors.
- SimulationVerification: 176 checks, 0 failures (final log: simulation-final-2560.log).
- PerformanceVerification: 82 checks, 0 failures (final log: performance-final-2560.log).
- Windowed DebugVisualVerification: 17 checks, 0 failures (visual-final-fixture.log); final screenshots were inspected for panel layout, removal of sheep vision controls, and retained wolf/dog overlays.
- Final screenshots: ../ecs-visuals/2026-11-16T11-59-32_65688/ (all-animals.png, parameters.png, sheep-parameters.png and other fixture captures).
- AGENTS.md contains exactly 60 physical lines, including blank lines. git diff --check passed.

## Windowed performance

Seed 1337; GL Compatibility; 1280 x 720 viewport; vsync disabled; 60 FPS cap; HUD, overlay and animals enabled; stages sampling; 5 seconds warmup + 30 seconds measurement. Benchmarks ran serially using isolated pre-edit sources. The 2560 comparison copy changes only arena_size in the pre-edit config.

| Scenario | Runs per version | Before FPS | After FPS | Before step ms | After step ms | Before frame P95 ms | After frame P95 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| 276 animals, 1280 x 720 arena | 3/3 | 38.28 | 57.89 | 15.69 | 12.98 | 80.16 | 21.02 |
| 1000 animals, fixed 1280 x 720 arena | 3/3 | 3.41 | 6.23 | 72.25 | 38.97 | 393.86 | 197.87 |
| 276 animals, current 2560 x 1440 arena | 1/1 | 52.38 | 57.52 | 12.89 | 13.03 | 34.19 | 19.07 |

Three-run groups report medians of each metric. The current 2560 arena has a single comparison pair, which is a check rather than a three-run performance conclusion.

| Scenario | Queries/step before -> after | Grid ms before -> after | Perception ms before -> after | Simulation ms/frame before -> after | Steps/frame before -> after |
|---|---:|---:|---:|---:|---:|
| default | 298.9 -> 96.0 | 0.23 -> 1.12 | 9.78 -> 5.87 | 22.83 -> 13.46 | 1.51 -> 1.04 |
| 1000 | 1054.0 -> 299.2 | 0.75 -> 2.07 | 52.68 -> 19.88 | 288.98 -> 155.88 | 4.00 -> 4.00 |
| 2560 | 325.5 -> 118.4 | 0.26 -> 2.15 | 6.34 -> 4.87 | 14.42 -> 13.55 | 1.12 -> 1.04 |

## Limits and behavior changes

- Removing sheep FOV intentionally changes trajectories and captures. Each run records initial/final populations, captures and simulated time; wall-clock runs do not necessarily advance the same simulation duration under load.
- Full Grid rebuild and shared-statistics time increased; reduced perception cost must be considered together with that increase.
- The 1000-animal runs remain far below 60 FPS; neither packed layout nor reversing pair traversal proves scalability by itself.
- Background applications were left running. These are observed results on this machine, not an isolated hardware benchmark or a GPU timing measurement.
- Headless smoke timings are diagnostic only and are not used as desktop FPS evidence.
- Grid-level flock and protection statistics approximate circular neighborhoods. Smooth flock flow and game feel still require human desktop acceptance; automated UI input and screenshot inspection are separate evidence.
- The visual test uses an explicit 1280 x 720 fixture for its three-animal interaction screenshots so the user's larger authored arena cannot move the fixture off camera.

Full per-run metadata, per-frame mean/P95 metrics, exclusive stage costs and result paths are in comparison.json.
