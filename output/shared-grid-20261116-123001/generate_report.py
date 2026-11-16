import json
import statistics
from pathlib import Path

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent.parent
GROUPS = ["baseline-276", "adaptive-276", "baseline-1000", "adaptive-1000"]
METRICS = ["average_fps", "frame_p95_ms", "step_mean_ms", "step_p95_ms", "steps_per_frame_mean", "simulation_per_frame_mean_ms", "simulation_per_frame_p95_ms", "simulation_seconds_advanced", "simulation_wall_ratio", "spatial_queries_per_step", "spatial_candidates_per_query"]
selected = {}
summaries = {}
for group in GROUPS:
    rows = []
    for path in sorted((OUT / group / "output/performance").glob("*/result.json")):
        result = json.loads(path.read_text(encoding="utf-8-sig"))
        label = result["label"]
        if group == "baseline-276" and label not in ["baseline_276_clean", "baseline_276_fresh_2", "baseline_276_fresh_3"]:
            continue
        if group == "baseline-1000" and "fresh" not in label:
            continue
        assert result["headless"] is False
        assert result["sampling"] == "stages" and result["script_profiler_active"] is False
        assert result["arena_size"] == [2560.0, 1440.0]
        assert result["max_fps"] == 60 and result["visibility"] == {"animals": True, "hud": True, "overlay": "on"}
        row = {key: value for key, value in result.items() if key != "samples"}
        row["evidence"] = path.relative_to(OUT).as_posix()
        rows.append(row)
    assert len(rows) == 3, (group, len(rows))
    selected[group] = rows
    summary = {key: statistics.median(row[key] for row in rows) for key in METRICS}
    summary["stages_mean_ms"] = {key: statistics.median(row["stages_mean_ms"][key] for row in rows) for key in rows[0]["stages_mean_ms"]}
    summary["decision_and_steering_ms"] = statistics.median(row["stages_mean_ms"]["Decision"] + row["stages_mean_ms"].get("Steering", 0.0) for row in rows)
    summary["preprocessing_mean_per_step"] = {key: statistics.median(row["preprocessing_mean_per_step"][key] for row in rows) for key in rows[0].get("preprocessing_mean_per_step", {})}
    summaries[group] = summary

lines = ["# Shared grid and batched steering implementation", "", "## Implementation", "",
    "- All three species still execute their existing behavior trees every fixed step. Tasks write motion intents; systems batch steering and strategy/collect geometry before movement. Wandering RNG and action side effects retain their original order.",
    "- Grid pressure uses bilinear corner samples in cells containing at least four sheep. Sparse cells retain exact individual pressure, avoiding four-sample setup for fewer than four readers. Wolf danger and dog influence gates always use actual source distances; capture and howl interactions remain exact after movement.",
    "- Dogs share count-weighted actual sheep centers by anchor cell. Candidate preparation is lazy: returning dogs need only the center. Each dog retains its own FOV, last-seen memory, patrol angle and assignment rules.",
    "- Added exclusive Steering timing and benchmark result_version=4. Preset version remains 5; default configuration and existing uniform spawn_initial are unchanged.",
    "- No threading, GPU compute, alternative state machine, dirty-grid ledger or third-party addon edits.", "", "## Verification", "",
    "- SimulationVerification: 225 checks, zero failures, including dense/sparse pressure transitions, exact radius gates, row reuse, shared centers and independent dog vision.",
    "- PerformanceVerification: 84 checks, zero failures. Configuration-dependent assertions now derive counts/scaling from their fixture.",
    "- Windowed DebugVisualVerification: 25 checks, zero failures; final screenshots are under ../ecs-visuals/2026-11-16T12-49-31_42976/.",
    "- Stage-one equivalence: 180 consecutive fixed-step state records at a 30-animal fixture match the baseline exactly, including RNG, motion, decisions and target memory. This equivalence applies to the batching phase, before spatial approximations.",
    "- git diff --check passed. Godot 4.7.2 executed the scripts; no engine rebuild is required.", "", "## Windowed measurements", "",
    "Main scene and production uniform spawn_initial, fixed 2560 x 1440 arena, seed 1337; 1280 x 720 viewport, Compatibility renderer, vsync off, 60 FPS cap. Animals/HUD/overlay enabled; stages sampling; script profiler off. Each run has 5 wall seconds warmup and 30 wall seconds measurement. Runs are serial. Existing editor/background applications remain open; these are observed machine results, not hardware-isolated CPU/GPU benchmarks.", "",
    "Earlier measurements drifted substantially. The main comparison below uses the clean/fresh baseline retests and final adaptive implementation, three runs each. Early baselines, prototype runs and intermediate diagnostics are retained separately and excluded from these medians.", "",
    "| Animals | Version | FPS | Step mean ms | Step P95 ms | Frame P95 ms | Simulation/frame ms | Steps/frame | Simulated seconds advanced |",
    "|---|---|---:|---:|---:|---:|---:|---:|---:|"]
for total in [276, 1000]:
    for version in ["baseline", "adaptive"]:
        row = summaries[f"{version}-{total}"]
        lines.append(f"| {total} | {version} | {row['average_fps']:.2f} | {row['step_mean_ms']:.3f} | {row['step_p95_ms']:.2f} | {row['frame_p95_ms']:.2f} | {row['simulation_per_frame_mean_ms']:.2f} | {row['steps_per_frame_mean']:.2f} | {row['simulation_seconds_advanced']:.2f} |")
lines += ["", "Each column is the median of its three run metrics; stage medians need not sum exactly to the median step time.", "",
    "| Animals | Step-time change | Decision + Steering before / after ms | Perception before / after ms | SpatialBuild before / after ms |",
    "|---|---:|---:|---:|---:|"]
for total in [276, 1000]:
    before, after = summaries[f"baseline-{total}"], summaries[f"adaptive-{total}"]
    change = (after["step_mean_ms"] / before["step_mean_ms"] - 1.0) * 100.0
    lines.append(f"| {total} | {change:+.1f}% | {before['decision_and_steering_ms']:.3f} / {after['decision_and_steering_ms']:.3f} | {before['stages_mean_ms']['Perception']:.3f} / {after['stages_mean_ms']['Perception']:.3f} | {before['stages_mean_ms']['SpatialBuild']:.3f} / {after['stages_mean_ms']['SpatialBuild']:.3f} |")
lines += ["", "## Individual runs", "", "| Group / label | FPS | Step ms | Frame P95 ms | Start counts -> end counts (sheep/wolf/dog) | Captures | Evidence |", "|---|---:|---:|---:|---|---:|---|"]
for group, rows in selected.items():
    for row in rows:
        lines.append(f"| {row['label']} | {row['average_fps']:.2f} | {row['step_mean_ms']:.3f} | {row['frame_p95_ms']:.2f} | {row['initial_counts']} -> {row['final_counts']} | {row.get('captures_during_measurement', '?')} | [result]({row['evidence']}) |")
lines += ["", "## Preprocessing and interpretation", ""]
for total in [276, 1000]:
    counters = summaries[f"adaptive-{total}"]["preprocessing_mean_per_step"]
    lines.append(f"- {total} animals, median per-step counters: " + ", ".join(f"{key}={value:.2f}" for key, value in counters.items()) + ".")
lines += [
    "- pressure_source_pairs counts source contributions at field sample points only; it does not include exact pressure evaluations in sparse cells.",
    "- Few anchor cells are shared in these uniform scenes because protection assignments spread dogs out. The sharing facility is verified but cannot be credited with a broad speedup here. Lazy candidate preparation avoids work for returning dogs regardless of sharing.",
    "- The first full-field prototype regressed: sample preparation/readback outweighed sharing in sparse regions. A later version prepared four samples only for cells with at least four sheep and retained exact sparse-cell evaluation. Prototype results are not presented as final performance.",
    "- Intermediate single-run diagnostics: stage1-1000 (batching only), stage2-1000 (batching + initial full pressure field). They precede the final sparse fallback and lazy candidate correction and are diagnostic, not independent controlled performance conclusions.",
    "- At 276 animals, mean step time is effectively flat, while median per-run step P95 regresses from 12.78 to 13.90 ms. Frame P95 improves, but this does not erase the per-step tail regression. Run-to-run machine variability limits precision of small differences.",
    "- The final 1000-animal scenario remains far below 60 FPS. Frame simulation may contain four fixed steps, so per-step cost must not be presented as frame cost. Simulation progress is slower than wall time under load.",
    "- Initial totals are 276 or 1000; captures remain enabled. Warmup and measurement both reduce live populations. Grid approximations change trajectories, captures and subsequent work, so these are end-to-end workload observations rather than exact equal-trajectory speedups.",
    "- Dog grouping changes the local-region reference to the anchor cell center; its patrol center still uses actual sheep positions. Pressure vectors interpolate in dense cells; exact radius gates prevent out-of-range danger. Density transitions switch to exact evaluation and can change vector values.",
    "- Automated viewport/input checks and screenshot inspection do not establish smooth flock flow, pressure feel, or absence of visible patrol-center jumps. Human desktop acceptance remains pending. No GPU timing was collected.", "", "## Evidence and source preservation", "",
    "Main data: comparison.json, changed-files.json, SimulationVerification-adaptive-final.log, PerformanceVerification-adaptive-final.log, visual-adaptive.log. Original snapshots, intermediate versions, raw launcher logs and failed exploratory logs are preserved without overwriting historical runs.",
    "The production source matches the adaptive-1000 benchmark snapshot. The authored CFG remains semantically identical to the initial 1000-animal baseline; only isolated benchmark copies override population. Existing unrelated worktree changes were retained."]

for folder in ["Scripts", "Resources", "Prefabs", "Levels"]:
    for path in (ROOT / folder).rglob("*"):
        if path.is_file():
            copy = OUT / "adaptive-1000" / path.relative_to(ROOT)
            assert copy.exists(), path
            try:
                assert path.read_text(encoding="utf-8") == copy.read_text(encoding="utf-8"), path
            except UnicodeError:
                assert path.read_bytes() == copy.read_bytes(), path

errors = []
for group in GROUPS:
    for launcher in (OUT / group / "output/performance").glob("*/launcher.json"):
        state = json.loads(launcher.read_text(encoding="utf-8-sig"))
        relevant = any(row["evidence"].endswith(state.get("result_path", "NO_RESULT").removeprefix("res://")) for row in selected[group])
        if relevant:
            assert state["exit_code"] == 0 and state["has_result"], launcher
            stderr = (launcher.parent / "stderr.log").read_text(encoding="utf-8-sig").strip()
            if stderr:
                errors.append({"launcher": str(launcher), "stderr": stderr})
assert not errors, errors
(OUT / "comparison.json").write_text(json.dumps({"medians": summaries, "runs": selected, "stderr": errors}, indent=2), encoding="utf-8")
(OUT / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(json.dumps(summaries, indent=2))
print(OUT / "report.md")
