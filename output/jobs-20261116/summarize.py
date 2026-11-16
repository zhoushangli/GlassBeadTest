import hashlib
import json
import statistics
from pathlib import Path

root = Path.cwd()
evidence = root / "output/jobs-20261116"
records = []
for path in sorted((root / "output/performance").glob("*jobs_*/result.json")):
    result = json.loads(path.read_text(encoding="utf-8"))
    result["evidence_path"] = str(path.relative_to(root))
    records.append(result)
final = [r for r in records if r["label"].startswith("jobs_final_")]
assert len(final) == 6, "Expected three alternating serial/parallel pairs"
metrics = ["step_mean_ms", "step_p95_ms", "simulation_per_frame_mean_ms", "simulation_per_frame_p95_ms", "steps_per_frame_mean", "average_fps", "frame_p95_ms", "simulation_wall_ratio"]
summary = {}
for mode in ["serial", "parallel"]:
    group = [r for r in final if r["jobs_mode"] == mode]
    assert len(group) == 3
    summary[mode] = {metric: statistics.median(r[metric] for r in group) for metric in metrics}
    summary[mode]["job_timings_mean_ms"] = {stage: {metric: statistics.median(r["job_timings_mean_ms"][stage][metric] for r in group) for metric in ["prepare_ms", "dispatch_ms", "wait_ms", "execute_ms", "submit_ms", "total_ms"]} for stage in ["Sheep", "Wolf", "DogAnchor", "Dog", "Grid"]}
    summary[mode]["runs"] = [{key: r[key] for key in ["label", "evidence_path", "initial_counts", "final_counts", "step_mean_ms", "step_p95_ms", "average_fps", "simulation_per_frame_mean_ms"]} for r in group]
serial = summary["serial"]["step_mean_ms"]
parallel = summary["parallel"]["step_mean_ms"]
summary["step_time_reduction_pct"] = (1 - parallel / serial) * 100
summary["step_throughput_ratio"] = serial / parallel
summary["protocol"] = {key: final[0][key] for key in ["engine", "cpu", "gpu", "renderer", "viewport", "arena_size", "configured_counts", "seed", "max_fps", "vsync", "visibility", "warmup_wall_seconds", "job_workers", "job_stages"]}
summary["source_sha256"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path("Scripts/Core/JobService.gd"), Path("Scripts/Core/GameplayEngine.gd"), Path("Scripts/Core/GridService.gd"), *Path("Scripts/Job").glob("*.gd"), *Path("Scripts/ECS/Systems").glob("*.gd")]}
summary["tests"] = {}
for name, filename in [("JobVerification", "JobVerification-acceptance.log"), ("SimulationVerification", "SimulationVerification-packed-v2.log"), ("PerformanceVerification", "PerformanceVerification-packed-v2.log"), ("DebugVisualVerification", "DebugVisualVerification-acceptance.log")]:
    raw = (evidence / filename).read_bytes()
    text = raw.decode("utf-8", errors="replace")
    assert "failures=0" in text and "SCRIPT ERROR" not in text and "ERROR:" not in text, filename
    summary["tests"][name] = [line.strip() for line in text.splitlines() if "VERIFICATION checks=" in line]
(evidence / "measurements.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
lines = ["JobService implementation and normal-scene measurements", "", "Final protocol: 1000 configured animals (870 sheep / 87 wolves / 43 dogs), 1280x720 Compatibility, HUD/animals/overlay on, VSync off, FPS cap 60. Three alternating pairs; each 5s warmup + 30s measurement. Values below are medians of run means/percentiles, not pooled percentiles.", "", "Default parallel stages: Sheep, DogAnchor, Grid. Wolf and Dog retain job implementations but execute serially because earlier all-stage measurements showed regression/no clear gain. Four outstanding tasks maximum; engine owns worker threads.", "", "metric | serial | default parallel"]
for metric in metrics:
    lines.append(f"{metric} | {summary['serial'][metric]:.6f} | {summary['parallel'][metric]:.6f}")
lines.extend(["", f"Step-time reduction: {summary['step_time_reduction_pct']:.2f}%; step throughput: {summary['step_throughput_ratio']:.3f}x.", "", "Job stage totals (ms/step; included in Simulation/SpatialBuild/Perception):"])
for stage in ["Sheep", "Wolf", "DogAnchor", "Dog", "Grid"]:
    lines.append(f"{stage}: serial={summary['serial']['job_timings_mean_ms'][stage]['total_ms']:.6f}; parallel={summary['parallel']['job_timings_mean_ms'][stage]['total_ms']:.6f}")
lines.extend(["", "Behavior: dog anchor scoring reads one old-anchor snapshot, preserving coverage penalty; target claims remain centralized. Shared coverage counts are computed once per selection round, subtracting the dog's own old anchor. Sheep results use packed batch columns. RNG remains on the main thread in stable order. JobService collects completions and invokes concrete jobs' apply_result at the stage barrier. Reset/shutdown reclaim tasks and discard unapplied results.", "", "The serial control includes the same new dog rule, shared-coverage preparation and packed sheep results. Its difference from parallel isolates scheduling; it is not the original implementation. jobs_original_baseline is one earlier observational run and is not a controlled estimate of total before/after improvement.", "", "Earlier/pre-packed all-stage runs and 2/4/8 worker probes are retained under output/performance and source snapshots under pre-packed. Eight-way scheduling was slower. These earlier versions are not substituted for final measurements.", "", "Wall-clock runs advance different numbers of simulation steps and can have different surviving sheep counts; exact per-step serial/parallel state and RNG equivalence is verified separately. GPU time is unavailable. Automated screenshots/input checks do not establish natural movement or human visual acceptance.", "", "Verification:"])
for name, lines_found in summary["tests"].items():
    lines.extend(lines_found)
lines.extend(["", "Raw final results:"])
lines.extend(r["evidence_path"] for r in final)
(evidence / "report.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(json.dumps({"serial_ms": serial, "parallel_ms": parallel, "reduction_pct": summary["step_time_reduction_pct"], "tests": summary["tests"]}, ensure_ascii=False, indent=2))
