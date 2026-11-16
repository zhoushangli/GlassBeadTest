# Shared grid and batched steering implementation

## Implementation

- All three species still execute their existing behavior trees every fixed step. Tasks write motion intents; systems batch steering and strategy/collect geometry before movement. Wandering RNG and action side effects retain their original order.
- Grid pressure uses bilinear corner samples in cells containing at least four sheep. Sparse cells retain exact individual pressure, avoiding four-sample setup for fewer than four readers. Wolf danger and dog influence gates always use actual source distances; capture and howl interactions remain exact after movement.
- Dogs share count-weighted actual sheep centers by anchor cell. Candidate preparation is lazy: returning dogs need only the center. Each dog retains its own FOV, last-seen memory, patrol angle and assignment rules.
- Added exclusive Steering timing and benchmark result_version=4. Preset version remains 5; default configuration and existing uniform spawn_initial are unchanged.
- No threading, GPU compute, alternative state machine, dirty-grid ledger or third-party addon edits.

## Verification

- SimulationVerification: 225 checks, zero failures, including dense/sparse pressure transitions, exact radius gates, row reuse, shared centers and independent dog vision.
- PerformanceVerification: 84 checks, zero failures. Configuration-dependent assertions now derive counts/scaling from their fixture.
- Windowed DebugVisualVerification: 25 checks, zero failures; final screenshots are under ../ecs-visuals/2026-11-16T12-49-31_42976/.
- Stage-one equivalence: 180 consecutive fixed-step state records at a 30-animal fixture match the baseline exactly, including RNG, motion, decisions and target memory. This equivalence applies to the batching phase, before spatial approximations.
- git diff --check passed. Godot 4.7.2 executed the scripts; no engine rebuild is required.

## Windowed measurements

Main scene and production uniform spawn_initial, fixed 2560 x 1440 arena, seed 1337; 1280 x 720 viewport, Compatibility renderer, vsync off, 60 FPS cap. Animals/HUD/overlay enabled; stages sampling; script profiler off. Each run has 5 wall seconds warmup and 30 wall seconds measurement. Runs are serial. Existing editor/background applications remain open; these are observed machine results, not hardware-isolated CPU/GPU benchmarks.

Earlier measurements drifted substantially. The main comparison below uses the clean/fresh baseline retests and final adaptive implementation, three runs each. Early baselines, prototype runs and intermediate diagnostics are retained separately and excluded from these medians.

| Animals | Version | FPS | Step mean ms | Step P95 ms | Frame P95 ms | Simulation/frame ms | Steps/frame | Simulated seconds advanced |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 276 | baseline | 58.39 | 10.444 | 12.78 | 17.91 | 10.66 | 1.02 | 29.80 |
| 276 | adaptive | 59.67 | 10.332 | 13.90 | 16.71 | 10.55 | 1.01 | 30.00 |
| 1000 | baseline | 6.71 | 36.721 | 41.68 | 175.97 | 146.88 | 4.00 | 13.47 |
| 1000 | adaptive | 7.26 | 34.197 | 37.83 | 151.34 | 136.79 | 4.00 | 14.53 |

Each column is the median of its three run metrics; stage medians need not sum exactly to the median step time.

| Animals | Step-time change | Decision + Steering before / after ms | Perception before / after ms | SpatialBuild before / after ms |
|---|---:|---:|---:|---:|
| 276 | -1.1% | 3.757 / 3.571 | 3.375 / 3.396 | 2.046 / 2.065 |
| 1000 | -6.9% | 12.171 / 10.675 | 15.798 / 15.224 | 3.798 / 3.672 |

## Individual runs

| Group / label | FPS | Step ms | Frame P95 ms | Start counts -> end counts (sheep/wolf/dog) | Captures | Evidence |
|---|---:|---:|---:|---|---:|---|
| baseline_276_clean | 58.39 | 10.444 | 17.91 | [227, 24, 12] -> [215, 24, 12] | 12 | [result](baseline-276/output/performance/2026-11-16T12-40-49_baseline_276_clean_50704_2401549/result.json) |
| baseline_276_fresh_2 | 59.98 | 10.101 | 16.69 | [227, 24, 12] -> [215, 24, 12] | 12 | [result](baseline-276/output/performance/2026-11-16T12-45-22_baseline_276_fresh_2_55824_1916717/result.json) |
| baseline_276_fresh_3 | 54.14 | 11.482 | 28.61 | [227, 24, 12] -> [215, 24, 12] | 12 | [result](baseline-276/output/performance/2026-11-16T12-46-01_baseline_276_fresh_3_25308_2229431/result.json) |
| adaptive_276_1 | 59.99 | 10.647 | 16.71 | [228, 24, 12] -> [215, 24, 12] | 13 | [result](adaptive-276/output/performance/2026-11-16T12-49-35_adaptive_276_1_58128_2114041/result.json) |
| adaptive_276_2 | 58.60 | 10.332 | 16.92 | [228, 24, 12] -> [215, 24, 12] | 13 | [result](adaptive-276/output/performance/2026-11-16T12-50-13_adaptive_276_2_45316_2233791/result.json) |
| adaptive_276_3 | 59.67 | 10.323 | 16.70 | [228, 24, 12] -> [215, 24, 12] | 13 | [result](adaptive-276/output/performance/2026-11-16T12-50-51_adaptive_276_3_54936_1940767/result.json) |
| baseline_1000_fresh_1 | 6.81 | 36.462 | 184.53 | [822, 87, 43] -> [790, 87, 43] | 32 | [result](baseline-1000/output/performance/2026-11-16T12-46-39_baseline_1000_fresh_1_42232_2506217/result.json) |
| baseline_1000_fresh_2 | 6.71 | 36.878 | 175.97 | [822, 87, 43] -> [790, 87, 43] | 32 | [result](baseline-1000/output/performance/2026-11-16T12-47-18_baseline_1000_fresh_2_67024_2544136/result.json) |
| baseline_1000_fresh_3 | 6.66 | 36.721 | 166.82 | [822, 87, 43] -> [791, 87, 43] | 31 | [result](baseline-1000/output/performance/2026-11-16T12-47-58_baseline_1000_fresh_3_66008_3207441/result.json) |
| adaptive_1000_1 | 7.26 | 34.197 | 150.71 | [822, 87, 43] -> [805, 87, 43] | 17 | [result](adaptive-1000/output/performance/2026-11-16T12-51-31_adaptive_1000_1_54336_2983498/result.json) |
| adaptive_1000_2 | 7.37 | 33.689 | 151.34 | [822, 87, 43] -> [804, 87, 43] | 18 | [result](adaptive-1000/output/performance/2026-11-16T12-52-09_adaptive_1000_2_70736_2396876/result.json) |
| adaptive_1000_3 | 6.99 | 34.831 | 166.85 | [822, 87, 43] -> [805, 87, 43] | 17 | [result](adaptive-1000/output/performance/2026-11-16T12-52-48_adaptive_1000_3_59196_2467259/result.json) |

## Preprocessing and interpretation

- 276 animals, median per-step counters: dog_candidate_groups=7.35, dog_group_hits=0.00, dog_groups=12.00, pressure_samples=1.62, pressure_source_pairs=1.54.
- 1000 animals, median per-step counters: dog_candidate_groups=19.84, dog_group_hits=0.03, dog_groups=42.97, pressure_samples=68.32, pressure_source_pairs=66.72.
- pressure_source_pairs counts source contributions at field sample points only; it does not include exact pressure evaluations in sparse cells.
- Few anchor cells are shared in these uniform scenes because protection assignments spread dogs out. The sharing facility is verified but cannot be credited with a broad speedup here. Lazy candidate preparation avoids work for returning dogs regardless of sharing.
- The first full-field prototype regressed: sample preparation/readback outweighed sharing in sparse regions. A later version prepared four samples only for cells with at least four sheep and retained exact sparse-cell evaluation. Prototype results are not presented as final performance.
- Intermediate single-run diagnostics: stage1-1000 (batching only), stage2-1000 (batching + initial full pressure field). They precede the final sparse fallback and lazy candidate correction and are diagnostic, not independent controlled performance conclusions.
- At 276 animals, mean step time is effectively flat, while median per-run step P95 regresses from 12.78 to 13.90 ms. Frame P95 improves, but this does not erase the per-step tail regression. Run-to-run machine variability limits precision of small differences.
- The final 1000-animal scenario remains far below 60 FPS. Frame simulation may contain four fixed steps, so per-step cost must not be presented as frame cost. Simulation progress is slower than wall time under load.
- Initial totals are 276 or 1000; captures remain enabled. Warmup and measurement both reduce live populations. Grid approximations change trajectories, captures and subsequent work, so these are end-to-end workload observations rather than exact equal-trajectory speedups.
- Dog grouping changes the local-region reference to the anchor cell center; its patrol center still uses actual sheep positions. Pressure vectors interpolate in dense cells; exact radius gates prevent out-of-range danger. Density transitions switch to exact evaluation and can change vector values.
- Automated viewport/input checks and screenshot inspection do not establish smooth flock flow, pressure feel, or absence of visible patrol-center jumps. Human desktop acceptance remains pending. No GPU timing was collected.

## Evidence and source preservation

Main data: comparison.json, changed-files.json, SimulationVerification-adaptive-final.log, PerformanceVerification-adaptive-final.log, visual-adaptive.log. Original snapshots, intermediate versions, raw launcher logs and failed exploratory logs are preserved without overwriting historical runs.
The production source matches the adaptive-1000 benchmark snapshot. The authored CFG remains semantically identical to the initial 1000-animal baseline; only isolated benchmark copies override population. Existing unrelated worktree changes were retained.
