import json
from pathlib import Path
from statistics import median

study = Path(__file__).resolve().parent
rows = []
for phase in ("before", "after"):
    for number in range(1, 4):
        label = f"wolf-spatial-{phase}-{number}"
        paths = list(study.parent.glob(f"*_{label}_*/result.json"))
        assert len(paths) == 1, (label, paths)
        path = paths[0]
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        rows.append(dict(
            phase=phase, label=label, result=str(path.relative_to(study.parent)),
            wolf_call_ms=data["hotspots"]["WolfTarget"]["mean_per_call_ms"],
            wolf_calls=data["hotspots"]["WolfTarget"]["calls"],
            hunt_ms=data["stages_mean_ms"]["HuntUpdate"],
            step_ms=data["step_mean_ms"], p95_ms=data["step_p95_ms"],
            fps=data["average_fps"], wall_seconds=data["measured_wall_seconds"],
            sim_start=data["simulation_seconds_at_measurement_start"],
            sim_advanced=data["simulation_seconds_advanced"],
            initial_counts=data["initial_counts"], final_counts=data["final_counts"],
        ))
metrics = ("wolf_call_ms", "hunt_ms", "step_ms", "p95_ms", "fps")
medians = {phase: {key: median(row[key] for row in rows if row["phase"] == phase)
                   for key in metrics} for phase in ("before", "after")}
changes = {key: (medians["after"][key] / medians["before"][key] - 1) * 100
           for key in metrics}
summary = dict(runs=rows, medians=medians, change_percent=changes)
(study / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
lines = [
    "狼选猎物空间查询对比", "",
    "Godot 4.7.2-stable official ed1daf0bf；既有兼容 LimboAI；桌面 Compatibility。",
    "初始 870 羊 / 87 狼 / 43 狗，fixed 场地 1280×720，uniform_v1，固定种子 1337。",
    "VSync 关、不限帧、60 Hz 模拟；每次预热 5 秒墙钟、测量 30 秒墙钟、外部超时 120 秒。",
    "detailed 采样，不连接 Profiler；修改前后三次串行采样，后台负载未隔离。", "",
    "label | WolfTarget ms/次 | HuntUpdate ms/步 | Step ms/步 | P95 ms | FPS | 模拟推进 s",
]
for row in rows:
    lines.append(f'{row["label"]} | {row["wolf_call_ms"]:.4f} | {row["hunt_ms"]:.3f} | '
                 f'{row["step_ms"]:.3f} | {row["p95_ms"]:.3f} | {row["fps"]:.2f} | {row["sim_advanced"]:.3f}')
lines += ["", "三次运行中位数（WolfTarget 为各运行单次平均耗时的中位数）："]
for key in metrics:
    lines.append(f'{key}: {medians["before"][key]:.4f} -> {medians["after"][key]:.4f} ({changes[key]:+.2f}%)')
lines += ["", "限制：各运行推进的模拟时间及种群不同，整体耗时变化不能全部归因于本次修改。",
          "新增狼选猎物查询计入空间统计；WolfTarget 包含该查询，热点耗时存在嵌套，不能相加。",
          "保留原竞争评分全狼遍历；没有改变搜索频率、感知半径、狗和羊的行为。", "",
          "解析/导入通过；SimulationVerification 124 项、PerformanceVerification 85 项通过。",
          "原始结果路径（相对于 output/performance）："]
lines += [row["result"] for row in rows]
cost_bytes = (study / "search-cost.log").read_bytes()
cost_text = cost_bytes.decode("utf-16" if cost_bytes.startswith(b"\xff\xfe") else "utf-8-sig")
cost_line = next(line for line in cost_text.splitlines()
                 if line.startswith("SEARCH_COST "))
costs = json.loads(cost_line.removeprefix("SEARCH_COST "))
assert all(row["matching_candidates"] for row in costs)
cost_medians = {key: median(row[key] / row["queries"] / 1000 for row in costs)
                for key in ("full_collect_usec", "spatial_collect_usec", "competition_weight_usec")}
summary["initial_static_search_cost_ms_per_wolf"] = cost_medians
(study / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
lines += ["", "候选收集成本诊断（search-cost.log / SearchCost.gd）：",
          "固定种子的初始静止 1000 实体场景，统计关闭；每组遍历 87 只狼，共五组。",
          "尚未推进模拟或开始追捕；不能当作演化后的桌面基准。每组均先测全表收集，再测网格收集。",
          "全部候选集合及顺序一致；以下为每组平均值的中位数，单位 ms/狼：",
          f'全表收集 {cost_medians["full_collect_usec"]:.4f}；网格收集（包含排序）{cost_medians["spatial_collect_usec"]:.4f}；'
          f'原竞争评分 {cost_medians["competition_weight_usec"]:.4f}。',
          "正式采样的 WolfTarget 单次平均耗时中位数下降约 7.3%，但 HuntUpdate 与整体步耗时没有改善。",
          "候选收集成本减少，而保留的逐候选全狼竞争评分仍占主要成本；不据此扩大本轮修改范围。", "",
          "桌面交互：默认 276 实体启动、绘制和追捕已观察，无运行错误日志。",
          "桌面按键注入未可靠触发暂停/单步/重置，未将其记为人工交互验收通过；自动控制验证已通过。",
          "仅关闭本轮创建的预览，未停止用户编辑器。",
          "源码修改：Scripts/WolfController.gd；Tests/SimulationVerification.gd。",
          "EntityService.gd 与基线哈希一致；基线副本保存在本目录 before/ 下。"]
(study / "report.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(json.dumps(dict(medians=medians, change_percent=changes), indent=2))
