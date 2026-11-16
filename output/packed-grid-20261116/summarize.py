import json
import statistics
from pathlib import Path

evidence = Path(__file__).resolve().parent
project = evidence.parent.parent
sources = [
    evidence / "before-project/output/performance",
    evidence / "before-2560-project/output/performance",
    project / "output/performance",
]
rows = []
for source in sources:
    for path in source.glob("*/result.json"):
        result = json.loads(path.read_text(encoding="utf-8"))
        if result.get("label", "").startswith(("packed_before_", "packed_after_")):
            result["evidence_path"] = str(path.relative_to(project)).replace("\\", "/")
            rows.append(result)

metrics = [
    "average_fps", "frame_p95_ms", "step_mean_ms", "step_p95_ms",
    "steps_per_frame_mean", "steps_per_frame_p95",
    "simulation_per_frame_mean_ms", "simulation_per_frame_p95_ms",
    "spatial_queries_per_step", "spatial_candidates_per_query", "simulation_wall_ratio",
]
groups = {}
for scale in ["default", "1000", "2560"]:
    for version in ["before", "after"]:
        prefix = f"packed_{version}_{scale}"
        runs = [row for row in rows if row["label"] == prefix or row["label"].startswith(prefix + "_")]
        if not runs:
            continue
        summary = {"runs": len(runs), "arena_size": runs[0]["arena_size"]}
        summary.update({metric: statistics.median(row[metric] for row in runs) for metric in metrics})
        summary["stages_mean_ms"] = {
            stage: statistics.median(row["stages_mean_ms"][stage] for row in runs)
            for stage in runs[0]["stages_mean_ms"]
        }
        summary["evidence"] = [row["evidence_path"] for row in runs]
        groups[f"{version}_{scale}"] = summary

(evidence / "comparison.json").write_text(json.dumps({"groups": groups, "runs": rows}, indent=2), encoding="utf-8")
lines = [
    "# Packed Grid implementation and verification",
    "",
    "Implemented: 60-line AGENTS, full-rebuild Packed GridService, shared sheep flock/alignment and dog protection-center statistics, source-driven wolf/dog pressure, removal of sheep FOV, configurable 30 px cells, preset version 4.",
    "The user changed the authored arena to 2560 x 1440 during this work; that edit was preserved.",
    "",
    "## Automated verification",
    "",
    "- Godot 4.7.2 import/parse completed without script errors.",
    "- SimulationVerification: 176 checks, 0 failures (final log: simulation-final-2560.log).",
    "- PerformanceVerification: 82 checks, 0 failures (final log: performance-final-2560.log).",
    "- Windowed DebugVisualVerification: 17 checks, 0 failures (visual-final-fixture.log); final screenshots were inspected for panel layout, removal of sheep vision controls, and retained wolf/dog overlays.",
    "- Final screenshots: ../ecs-visuals/2026-11-16T11-59-32_65688/ (all-animals.png, parameters.png, sheep-parameters.png and other fixture captures).",
    "- AGENTS.md contains exactly 60 physical lines, including blank lines. git diff --check passed.",
    "",
    "## Windowed performance",
    "",
    "Seed 1337; GL Compatibility; 1280 x 720 viewport; vsync disabled; 60 FPS cap; HUD, overlay and animals enabled; stages sampling; 5 seconds warmup + 30 seconds measurement. Benchmarks ran serially using isolated pre-edit sources. The 2560 comparison copy changes only arena_size in the pre-edit config.",
    "",
    "| Scenario | Runs per version | Before FPS | After FPS | Before step ms | After step ms | Before frame P95 ms | After frame P95 ms |",
    "|---|---:|---:|---:|---:|---:|---:|---:|",
]
for scale, title in [("default", "276 animals, 1280 x 720 arena"), ("1000", "1000 animals, fixed 1280 x 720 arena"), ("2560", "276 animals, current 2560 x 1440 arena")]:
    before, after = groups.get(f"before_{scale}"), groups.get(f"after_{scale}")
    if not before or not after:
        continue
    lines.append(f"| {title} | {before['runs']}/{after['runs']} | {before['average_fps']:.2f} | {after['average_fps']:.2f} | {before['step_mean_ms']:.2f} | {after['step_mean_ms']:.2f} | {before['frame_p95_ms']:.2f} | {after['frame_p95_ms']:.2f} |")
lines += [
    "",
    "Three-run groups report medians of each metric. The current 2560 arena has a single comparison pair, which is a check rather than a three-run performance conclusion.",
    "",
    "| Scenario | Queries/step before -> after | Grid ms before -> after | Perception ms before -> after | Simulation ms/frame before -> after | Steps/frame before -> after |",
    "|---|---:|---:|---:|---:|---:|",
]
for scale in ["default", "1000", "2560"]:
    before, after = groups.get(f"before_{scale}"), groups.get(f"after_{scale}")
    if not before or not after:
        continue
    lines.append(f"| {scale} | {before['spatial_queries_per_step']:.1f} -> {after['spatial_queries_per_step']:.1f} | {before['stages_mean_ms']['SpatialBuild']:.2f} -> {after['stages_mean_ms']['SpatialBuild']:.2f} | {before['stages_mean_ms']['Perception']:.2f} -> {after['stages_mean_ms']['Perception']:.2f} | {before['simulation_per_frame_mean_ms']:.2f} -> {after['simulation_per_frame_mean_ms']:.2f} | {before['steps_per_frame_mean']:.2f} -> {after['steps_per_frame_mean']:.2f} |")
lines += [
    "",
    "## Limits and behavior changes",
    "",
    "- Removing sheep FOV intentionally changes trajectories and captures. Each run records initial/final populations, captures and simulated time; wall-clock runs do not necessarily advance the same simulation duration under load.",
    "- Full Grid rebuild and shared-statistics time increased; reduced perception cost must be considered together with that increase.",
    "- The 1000-animal runs remain far below 60 FPS; neither packed layout nor reversing pair traversal proves scalability by itself.",
    "- Background applications were left running. These are observed results on this machine, not an isolated hardware benchmark or a GPU timing measurement.",
    "- Headless smoke timings are diagnostic only and are not used as desktop FPS evidence.",
    "- Grid-level flock and protection statistics approximate circular neighborhoods. Smooth flock flow and game feel still require human desktop acceptance; automated UI input and screenshot inspection are separate evidence.",
    "- The visual test uses an explicit 1280 x 720 fixture for its three-animal interaction screenshots so the user's larger authored arena cannot move the fixture off camera.",
    "",
    "Full per-run metadata, per-frame mean/P95 metrics, exclusive stage costs and result paths are in comparison.json.",
]
(evidence / "results.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(json.dumps(groups, indent=2))
