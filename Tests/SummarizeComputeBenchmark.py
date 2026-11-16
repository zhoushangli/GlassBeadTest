import hashlib
import json
import statistics
import sys
from pathlib import Path


def summarize(directory: Path, output: Path | None = None) -> None:
    runs = json.loads((directory / "runs.json").read_text(encoding="utf-8-sig"))
    assert runs, "No completed runs to summarize"
    for source in json.loads((directory / "source-hashes.json").read_text(encoding="utf-8-sig")):
        digest = hashlib.sha256(Path(source["Path"]).read_bytes()).hexdigest().upper()
        assert digest == source["Hash"], f"Source changed: {source['Path']}"

    results = []
    for run in runs:
        data = json.loads(Path(run["result"]).read_text(encoding="utf-8-sig"))
        assert data["renderer"] == "forward_plus"
        assert data["simulation_hz"] == 30
        assert data["compute"]["requested_backend"] == run["backend"]
        results.append((run, data))

    summary = {"source_hashes_verified": True, "matrix_complete": len(runs) == 12, "runs": runs, "populations": {}}
    lines = ["Forward+ compute shader 评估报告", "", "仅统计平均值与 P95。多次运行取各次结果的平均值；P95 列为各次 P95 的平均值。", "用户要求直接生成报告，后续测试已停止。", ""]
    for population in (2000, 5000):
        groups = {}
        for backend in ("cpu", "gpu"):
            samples = [data for run, data in results if run["population"] == population and run["backend"] == backend]
            if not samples:
                groups[backend] = {"run_count": 0}
                continue
            metrics = {"run_count": len(samples)}
            for field in ("average_fps", "frame_p95_ms", "actual_simulation_hz", "step_mean_ms", "simulation_per_frame_mean_ms"):
                metrics[field] = statistics.mean(data[field] for data in samples)
            for field in ("latency_ms", "processing_ms", "grid_ms", "prepare_ms", "execute_ms", "pack_ms", "upload_submit_ms", "gpu_ms", "readback_ms", "decode_ms", "apply_ms", "upload_bytes", "download_bytes"):
                for statistic in ("mean", "p95"):
                    values = [data["compute"]["metrics"][field][statistic] for data in samples if data["compute"]["metrics"][field]["count"]]
                    metrics[f"{field}_{statistic}"] = statistics.mean(values) if values else None
            metrics["applied_hz"] = [statistics.mean(data["compute"]["applied_hz"][kind] for data in samples) for kind in range(3)]
            metrics["requested_hz"] = [statistics.mean(data["compute"]["requests_hz"][kind] for data in samples) for kind in range(3)]
            metrics["arena_size"] = samples[0]["arena_size"]
            metrics["window_size"] = samples[0]["compute"]["window_size"]
            metrics["render_size"] = samples[0]["compute"]["render_size"]
            groups[backend] = metrics

        cpu, gpu = groups["cpu"], groups["gpu"]
        if not cpu["run_count"] or not gpu["run_count"]:
            groups["passed"] = None
            summary["populations"][population] = groups
            lines += [f"{population} 实体：缺少完整 CPU/GPU 对照，未验收。", ""]
            continue
        acceptance = {
            "end_to_end_latency_reduced_20_percent": gpu["latency_ms_mean"] <= cpu["latency_ms_mean"] * 0.8,
            "processing_cost_reduced_20_percent": gpu["processing_ms_mean"] <= cpu["processing_ms_mean"] * 0.8,
            "frame_p95_no_regression_over_5_percent": gpu["frame_p95_ms"] <= cpu["frame_p95_ms"] * 1.05,
            "simulation_hz_no_regression_over_5_percent": gpu["actual_simulation_hz"] >= cpu["actual_simulation_hz"] * 0.95,
            "species_apply_hz_no_regression_over_5_percent": all(gpu["applied_hz"][kind] >= cpu["applied_hz"][kind] * 0.95 for kind in range(3)),
            "latency_p95_no_regression_over_5_percent": gpu["latency_ms_p95"] <= cpu["latency_ms_p95"] * 1.05,
        }
        groups["acceptance"] = acceptance
        groups["repeats_complete"] = cpu["run_count"] == 3 and gpu["run_count"] == 3
        groups["passed"] = all(acceptance.values()) if groups["repeats_complete"] else None
        summary["populations"][population] = groups
        status = "通过" if groups["passed"] else "未通过性能门槛" if groups["repeats_complete"] else "仅单次探索对照，未完成三次复测"
        lines += [f"{population} 实体：{status}；CPU {cpu['run_count']} 次，GPU {gpu['run_count']} 次", f"场地 {cpu['arena_size']}；窗口 {cpu['window_size']}；渲染 {cpu['render_size']}"]
        for backend in ("cpu", "gpu"):
            m = groups[backend]
            lines.append(f"{backend.upper()}: FPS {m['average_fps']:.2f}；帧 P95 {m['frame_p95_ms']:.3f} ms；模拟 {m['actual_simulation_hz']:.2f} Hz；每步 {m['step_mean_ms']:.3f} ms；每帧模拟总计 {m['simulation_per_frame_mean_ms']:.3f} ms")
            lines.append(f"  网格+羊处理成本 {m['processing_ms_mean']:.3f} ms；快照到应用延迟 {m['latency_ms_mean']:.3f} ms / P95 {m['latency_ms_p95']:.3f} ms；应用频率 {m['applied_hz']}")
        lines.append("门槛：" + json.dumps(acceptance, ensure_ascii=False))
        lines.append("")
    summary["passed"] = all(group["passed"] for group in summary["populations"].values())
    lines += ["条件：种子 1337，30 Hz 模拟，羊狼狗各 12 Hz，每帧最多 2 步；每次预热 5 秒、测量 30 秒。", "固定密度：以 1000 实体 / 5120×2880 为基准，场地宽高乘以 sqrt(实体数/1000)。", "保留动物、HUD、overlay；VSync 关闭、FPS 无上限；同一 Forward+ 渲染器。", "processing_ms 是各处理阶段的成本之和；latency_ms 是快照捕获到主线程应用完成的实际端到端时间。", "readback_ms 包含 GPU 调度、执行和帧队列等待，不能解释为纯下载传输时间。", "GPU 时间来自 RenderingDevice 时间戳；不以 CPU 提交时间代替。", "CPU/GPU 异步完成时机不同，捕获和种群轨迹可能分化；各轮种群与捕获数量见原始结果。", "采用隔离副本中已完成的运行，副本源码哈希已核对；不混入并发基准、早期实现和后续未完成运行。", "自动检查和截图观察不等于长期人工游玩验收。"]
    output = output or directory
    output.mkdir(parents=True, exist_ok=True)
    (output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    (output / "REPORT.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    summarize(Path(sys.argv[1]), Path(sys.argv[2]) if len(sys.argv) > 2 else None)
