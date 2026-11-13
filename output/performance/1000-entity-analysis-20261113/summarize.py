import hashlib
import json
import re
import statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def load_runs():
    manifest = json.loads((HERE / 'manifest.json').read_text(encoding='utf-8-sig'))
    runs = {}
    for entry in manifest:
        path = entry.get('status', {}).get('result_path')
        if entry['exit_code'] == 0 and path:
            result_path = ROOT / path.removeprefix('res://')
            result = json.loads(result_path.read_text(encoding='utf-8'))
            result['_link'] = '../' + result_path.parent.name + '/result.json'
            result['_stdout'] = str(Path(entry['launcher']).parent / 'stdout.log')
            result['_stderr'] = str(Path(entry['launcher']).parent / 'stderr.log')
            runs[entry['label']] = result
    return manifest, runs


def number(value, places=2):
    return f'{value:.{places}f}'


def table(headers, rows):
    return ['| ' + ' | '.join(headers) + ' |', '| ' + ' | '.join(['---'] * len(headers)) + ' |'] + [
        '| ' + ' | '.join(str(c) for c in row) + ' |' for row in rows
    ] + ['']


def main():
    manifest, runs = load_runs()
    fixed = [r for label, r in runs.items() if label.startswith('fixed-stages-')]
    scaled = [r for label, r in runs.items() if label.startswith('scaled-stages-')]
    if len(fixed) != 3 or len(scaled) != 3 or len(runs) != 17:
        raise SystemExit(f'Incomplete suite: {len(runs)}/17 successful results')
    base = sorted(fixed, key=lambda r: r['step_mean_ms'])[1]
    detail = runs['fixed-detailed']
    profile = runs['fixed-profiler']
    median = lambda group, key: statistics.median(r[key] for r in group)
    stages = sorted(base['stages_mean_ms'].items(), key=lambda p: -p[1])
    profile_text = Path(profile['_stdout']).read_text(encoding='utf-8-sig')
    frame_blocks = re.split(r'^FRAME:.*$', profile_text, flags=re.MULTILINE)[1:]
    functions = []
    observations = {}
    pattern = r'^\d+:(.+)\r?\n\s*total:\s*([\d.eE+-]+)/[^\n]*?self:\s*([\d.eE+-]+)/[^\n]*?tcalls:\s*(\d+)'
    for index, block in enumerate(frame_blocks):
        for signature, total, own, calls in re.findall(pattern, block, re.MULTILINE):
            signature = signature.strip()
            if signature not in observations:
                observations[signature] = {'inclusive': [0.0] * len(frame_blocks), 'self': [0.0] * len(frame_blocks), 'calls': 0}
            observations[signature]['inclusive'][index] = float(total)
            observations[signature]['self'][index] = float(own)
            observations[signature]['calls'] += int(calls)
    for signature, values in observations.items():
        functions.append({'signature': signature, 'inclusive_seconds': sum(values['inclusive']), 'self_seconds': sum(values['self']),
                          'calls': values['calls'], 'median_self_ms': statistics.median(values['self']) * 1000.0,
                          'max_self_ms': max(values['self']) * 1000.0, 'frame_samples': len(frame_blocks)})
    (HERE / 'profiler-functions.json').write_text(json.dumps(functions, indent=2), encoding='utf-8')
    rows = []
    for entry in manifest:
        r = runs[entry['label']]
        rows.append([
            '[' + r['label'] + '](' + r['_link'] + ')',
            number(r.get('average_fps', r['loop_hz'])), number(r['frame_p95_ms'] if 'frame_p95_ms' in r else r['loop_p95_ms']),
            number(r['step_mean_ms']), number(r['step_p95_ms']), number(r['step_max_ms']),
            number(r['simulation_wall_ratio'], 3),
            '/'.join(map(str, r['initial_counts'])) + ' → ' + '/'.join(map(str, r['final_counts']))
        ])
    report = [
        '# 初始 1000 Entity 性能分析报告', '',
        f'原场地三次桌面基线的平均 FPS 中位数为 **{median(fixed, "average_fps"):.2f}**，每模拟步平均耗时中位数为 **{median(fixed, "step_mean_ms"):.2f} ms**。'
        f'当前距离 60 FPS／60 Hz 实时模拟的预算（每帧约 16.67 ms）有明显差距。', '',
        f'在代表性基线 `{base["label"]}` 中，最耗时阶段为 **{stages[0][0]}，{stages[0][1]:.2f} ms／步（{stages[0][1] / base["step_mean_ms"] * 100:.1f}%）**。'
        f'纯移动为 **{base["movement_mean_ms"]:.2f} ms／步**。瓶颈排序以本文的阶段、热点及 Profiler 证据为依据。', '',
        '## 测试环境与口径', '',
        f'- 引擎：{base["engine"].get("string", base["engine"])}；LimboAI 元数据和二进制 SHA-256 随每份 JSON 保存。',
        f'- CPU：{base["cpu"]}；GPU：{base["gpu"]}；渲染器：{base["renderer"]}。',
        '- 初始 870 羊、87 狼、43 狗；草点和节点不计入动物总数。固定种子 1337，初始动物位置均匀分布，采用既有 uniform_v1 布局。',
        '- 每次预热 5 秒墙钟，再测量至少 60 秒墙钟；串行启动，外部超时 120 秒。1280×720 视口，模拟 60 Hz；除 cap60 外均取消 FPS 上限，关闭 VSync。',
        '- 原场地 1280×720；scaled 同比扩大面积与草量，并把全场缩放到同一视口。因此 scaled 同时改变局部密度、草搜索工作量和显示比例，不能视为只改变一项变量。',
        '- 60 秒是实际经过时间，模拟可能推进不足 60 秒。捕获不被禁止，也不补充动物；预热结束时已可能少于 1000。每秒记录种群和模拟进度。',
        '- 运行时保留原有用户编辑器进程，未主动结束用户进程；测试不连接远程 Profiler。系统其他后台负载未隔离。',
        '- 基线采用阶段采样；off 用于观察采样开销；detailed 和 profiler 仅用于诊断。没有重新编译 Godot，没有修改默认 CFG 或行为规则。', '',
        '这些结果来自当前编辑器发行包运行项目，不能当作导出 Release 包的性能结论。', '',
        '## 全部运行结果', '',
        '表中时间均为毫秒，种群按羊／狼／狗排列；headless 行的第二列是循环 Hz，其余行为桌面 FPS。Frame P95 包括整次循环中的模拟、渲染与等待，不等于 GPU 时间。', '',
    ]
    report += table(['运行／原始结果', 'FPS／Hz', 'Frame P95', 'Step mean', 'Step P95', 'Step max', '模拟／墙钟', '测量开始 → 结束'], rows)
    report += [
        f'原场地三次平均 FPS 范围：{min(r["average_fps"] for r in fixed):.2f}～{max(r["average_fps"] for r in fixed):.2f}；'
        f'scaled 三次平均 FPS 中位数：{median(scaled, "average_fps"):.2f}，每步平均耗时中位数：{median(scaled, "step_mean_ms"):.2f} ms。', '',
        '## 模拟阶段与热点', '',
        f'阶段表采用每步平均耗时居中的基线 `{base["label"]}`；各阶段互斥。Preparation 合计草更新及预约统计；Cleanup 包含过期移除和模拟时钟、步数更新。', '',
    ]
    report += table(['阶段', '平均 ms／步', '占总步进'], [(name, number(value, 3), f'{value / base["step_mean_ms"] * 100:.1f}%') for name, value in stages])
    residual = base['step_mean_ms'] - sum(base['stages_mean_ms'].values())
    report += [
        f'阶段总和与总步进之差为 {residual:.9f} ms（浮点舍入误差）。总步进边界不包含窗口聚合、Benchmark 信号回调、HUD 或绘制；因此阶段占比不能当作完整帧占比。', '',
        '详细采样的热点表：耗时包含函数下层调用；每步指该步所有调用累计后再求平均，单次指总耗时除调用次数。热点属于上面的阶段内部，不能重复相加。', '',
    ]
    report += table(['热点', '总调用数', '平均 ms／步', '平均 ms／次', '累计 ms'], [
        (name, h['calls'], number(h['mean_per_step_ms'], 3), number(h['mean_per_call_ms'], 4), number(h['total_ms']))
        for name, h in sorted(detail['hotspots'].items(), key=lambda p: -p[1]['mean_per_step_ms'])
    ])
    slow_windows = sorted(detail['samples'], key=lambda s: -s['step_mean_ms'])[:4]
    report += ['详细档最慢的四个采样窗口如下。狗选目标的累计耗时集中在模拟时间约 4、8、12、14 秒附近，与 2 秒重分配周期对应，是长停顿的重要直接证据；这是窗口累计，不把它误称为单次函数或单个模拟步耗时。', '']
    report += table(['墙钟窗口结束 s', '模拟时间 s', '窗口步数', 'Step mean ms', '狗重分配次数', '狗重分配累计 ms'], [
        (number(s['wall_seconds']), number(s['simulation_seconds']), s['physics_steps'], number(s['step_mean_ms']), s['hotspots']['DogAnchor']['calls'], number(s['hotspots']['DogAnchor']['total_ms']))
        for s in slow_windows
    ])
    report += [f'即使仅在详细档账面上扣除 DogAnchor 的全部平均耗时，剩余仍为 {detail["step_mean_ms"] - detail["hotspots"]["DogAnchor"]["mean_per_step_ms"]:.2f} ms／步，明显超过 16.67 ms。这个算式不是优化收益预测，而是说明只解决重分配尖峰仍不足以达到实时目标，常态感知、狼选目标与决策成本也必须继续降低。', '']
    report += [
        f'空间工作量（详细档）：每步查询 {detail["spatial_queries_per_step"]:.1f} 次，每次平均候选 {detail["spatial_candidates_per_query"]:.1f} 个，'
        f'单次最大候选 {detail["spatial_max_candidates"]} 个，单格最大占用 {detail["spatial_max_occupancy"]} 只。候选尚未做圆形距离和物种筛选。', '',
        '源码对应关系与优化建议：', '',
        '- 狗选保护对象对每只羊计算评分，评分内再次遍历狗；当前 CFG 每 2 秒模拟时间重新分配，初始计时也一致，容易同一步集中执行。优先用热点和 Profiler 判断其对长步进的贡献；之后可讨论分散重分配时刻、复用覆盖统计。',
        '- 狼选猎物先遍历羊，再为候选羊遍历狼计算竞争权重。可讨论共享追踪计数、用空间候选缩小选猎物范围，须保留当前加权选择语义。',
        '- 邻居扫描和软分离重复遍历候选；应先区分返回候选的成本与候选过滤、向量运算成本，再考虑复用遍历或调整查询范围。',
        '- 羊选草遍历所有草点，部分评分改进候选还遍历狼；饥饿与草量变化会改变此成本。可讨论草候选筛选及安全检查复用，不能只根据早期短样本排除它。',
        '- 本次不实施上述优化，不引入 ECS、多线程、Compute Shader 或新服务框架。', '',
        '## 时间段、显示和测量开销', '',
        '以下按墙钟区间汇总；Step mean 按实际模拟步数加权，不能直接比较不同模拟进度的行为强度。', '',
    ]
    segment_rows = []
    for label in [base['label'], 'fixed-detailed']:
        r = runs[label]
        for start, end in [(0, 20), (20, 40), (40, 1000)]:
            ss = [s for s in r['samples'] if start < s['wall_seconds'] <= end]
            if not ss:
                continue
            steps = sum(s['physics_steps'] for s in ss)
            stage_mean = {k: sum(s['stages_mean_ms'][k] * s['physics_steps'] for s in ss) / max(1, steps) for k in r['stages_mean_ms']}
            segment_rows.append([label, f'{start}～{min(60, end)} s', f'{ss[0]["simulation_seconds"]:.2f}～{ss[-1]["simulation_seconds"]:.2f} s',
                                 f'{sum(ss[0][k] for k in ["sheep", "wolves", "dogs"])} → {sum(ss[-1][k] for k in ["sheep", "wolves", "dogs"])}',
                                 number(sum(s['step_mean_ms'] * s['physics_steps'] for s in ss) / max(1, steps)),
                                 max(stage_mean, key=stage_mean.get)])
    report += table(['运行', '墙钟区间', '样本模拟时间', '样本存活数', 'Step mean ms', '最耗时阶段'], segment_rows)
    comparisons = []
    base_fps = median(fixed, 'average_fps')
    base_step = median(fixed, 'step_mean_ms')
    for label in ['fixed-off', 'fixed-detailed', 'fixed-no-debug', 'fixed-lines', 'fixed-hide-animals', 'fixed-hide-grass', 'fixed-hide-both', 'fixed-cap60', 'fixed-closing']:
        r = runs[label]
        draws = [s['draw_calls'] for s in r['samples']]
        comparisons.append([label, number(r['average_fps']), f'{(r["average_fps"] / base_fps - 1) * 100:+.1f}%',
                            number(r['step_mean_ms'] - base_step), number(statistics.mean(draws))])
    report += table(['对照', '平均 FPS', '相对基线中位数', 'Step mean 差 ms', '每秒采样 draw calls 平均'], comparisons)
    closing = runs['fixed-closing']
    headless = runs['fixed-headless']
    report += [f'为检查运行期间的波动，末尾补测相同桌面基线：{closing["average_fps"]:.2f} FPS、{closing["step_mean_ms"]:.2f} ms／步；相对前三次基线中位数，步耗时变化 {(closing["step_mean_ms"] / base_step - 1) * 100:+.1f}%。这是额外控制组，未纳入最初三次基线中位数。', '',
               f'headless 的单步平均为 {headless["step_mean_ms"]:.2f} ms，反而比桌面基线慢。本轮未控制 CPU 亲和性、运行模式调度和热状态，因此不把这一差值解释为渲染成本。', '']
    report += [
        '各对照只测一次，帧率差受系统负载、热状态、模拟进度及种群变化影响，不能把小幅差异当成确定收益。关闭采样也保留既有总步进计时和 Benchmark 采集，故 off 表示关闭新增的阶段／空间／热点监视，不表示零测量开销。', '',
    ]
    report += table(['运行', 'HUD ms／刷新', '调试绘制 CPU ms／调用'], [
        (label, number(runs[label]['debug']['HUDRefresh']['mean_per_call_ms'], 4), number(runs[label]['debug']['OverlayDrawCPUTime']['mean_per_call_ms'], 4))
        for label in [base['label'], 'fixed-no-debug', 'fixed-lines']
    ])
    report += [
        '原场景使用 Sprite2D、Polygon2D 表现。隐藏动物或草仍保留其模拟与节点；测量差值是整体显示影响，不能精确分解为 GPU 时间。Compatibility 路径本轮未采集可靠 GPU 时间，因此 JSON 明确标记 gpu_timing_available=false。', '',
        '## Profiler 与验证限制', '',
        f'- 单独 Profiler 运行的 scripts profiling 状态：`{profile["script_profiler_active"]}`。原始函数排行保存在该运行的 stdout.log；其帧率不作为基线。',
        f'- 代表性基线实际记录 {base["physics_steps"]} 个模拟步和 {base["process_iterations"]} 次渲染循环，平均每循环 {base["physics_steps"] / base["process_iterations"]:.2f} 步。固定步长补步使低 FPS 下每帧执行多次模拟步；不能把 1 / StepMean 直接当成实际 FPS。',
        '- 解析／导入通过；PerformanceVerification 85 项、SimulationVerification 116 项通过。验证覆盖原生时间类型注册、秒转换、阶段求和、暂停零窗口、重置／停止清理，以及 off／stages／detailed 固定步数的随机数和动物状态一致性。',
        '- 编辑器 UI 目视验收未完成：Computer Use 应用访问批准等待超时。已验证回调秒值和 MONITOR_TYPE_TIME 类型；尚未目视确认实际列表与曲线的 ms 排版。',
        '- 本地 Godot 源码为 4.8 beta，测试使用 4.7.2 stable；未将不同版本源码的能力当作运行验证。',
        '- 本轮测量从预热后开始，不覆盖最初创建 1000 只动物、导入资源及首次完整感知的启动尖峰。', '',
        '- 基准使用均匀初始布局；普通场景的 spawn_initial 会把羊集中生成在中央区域，因此不能把本结果视为所有初始聚集布局的上限。', '',
        f'- 代表性基线在测量期间只推进 {base["simulation_seconds_advanced"]:.2f} 秒模拟时间；本报告不覆盖长时间草耗尽、持续饥饿及生态演化后的性能。', '',
        '## 复现与原始证据', '',
        '- [运行清单及启动日志路径](manifest.json)、[串行测试脚本](run-suite.ps1)、[报告生成脚本](summarize.py)。',
        '- [性能验证日志](verification.log)、[模拟验证日志](simulation-verification.log)、[导入日志](import.log)。',
        '- 使用项目 Tests/RunBenchmark.ps1；示例：`./Tests/RunBenchmark.ps1 -Entities 1000 -Scenario fixed -Sampling detailed -Warmup 5 -Duration 60 -TimeoutSeconds 120 -Label manual-detailed`。',
        '- 阶段／热点监视器的值保持数值；时间回调返回秒，编辑器显示 ms；JSON 的 `_ms` 字段仍为毫秒。旧合并字段含义保持不变，新增字段提供独立阶段。',
    ]
    ranked_hotspots = sorted(detail['hotspots'].items(), key=lambda p: -p[1]['mean_per_step_ms'])
    finding = '详细档中，前三个已测热点为：' + '；'.join(f'**{name}：{h["mean_per_step_ms"]:.2f} ms／步**' for name, h in ranked_hotspots[:3]) + '。此排序仅覆盖已布置的热点；其余感知逻辑仍需结合 Profiler 分析。'
    report[6:6] = [finding, '']
    if functions:
        profile_lines = [f'Profiler 的退出 ACCUMULATED 表为空，因此改用日志中实际输出的 **{len(frame_blocks)} 个 FRAME 函数快照**。以下按采样帧 Self 总和排序；Self 中位数与峰值按采样帧统计，Calls 只累计这些快照。快照含启动及预热，未覆盖所有帧，不能当作全程累计或与 60 秒阶段表相加。', '']
        profile_lines += table(['函数', '样本 Inclusive s', '样本 Self s', 'Self 中位数 ms／采样帧', 'Self 最大 ms／采样帧', '样本 Calls'], [
            (f['signature'], number(f['inclusive_seconds'], 3), number(f['self_seconds'], 3), number(f['median_self_ms'], 3), number(f['max_self_ms'], 3), f['calls'])
            for f in sorted(functions, key=lambda f: -f['self_seconds'])[:12]
        ])
    else:
        profile_lines = ['未在日志中解析到退出累计函数表；不能据此宣称已取得函数级热点证据。', '']
    idx = report.index('## 复现与原始证据')
    report[idx:idx] = profile_lines
    idx = report.index('## 复现与原始证据')
    findings = [
        '## 证据支持的优化优先级', '',
        '1. **先处理狗重分配尖峰。** 详细档每次选择约 31 ms，多个狗集中触发产生约 1.2～1.4 秒的窗口累计开销；Profiler 也直接记录到 _anchor_score 的单个采样帧 Self 峰值约 1.36 秒。应先讨论分散重分配时刻及减少重复覆盖评分。',
        '2. **细分羊的常态感知。** Profiler 样本中 SheepController.perceive 的 Self 总和最高，除子脚本调用外仍有明显开销。源码包含每步状态与饥饿维护、黑板写入和草安全判断；Self 也可能包含原生调用成本，当前不能把它全部归到某一行或 LimboAI 内部。_grass_unsafe 还会在选草之外被调用，不能只看 SheepGrass 热点就排除其成本。',
        '3. **减少候选后的重复处理及狼竞争评分。** 邻居扫描、软分离与 _prey_weight 均有函数级证据。先减少重复遍历和评分工作，再根据候选数量评估网格参数；仅改空间网格不足以解释或消除当前大部分耗时。',
        '4. **移动、HUD 与渲染调整排在上述模拟问题之后。** 纯移动约占基线步进的 2.7%；隐藏动物与草、关闭调试均未带来超出波动范围的改善。这说明它们目前不是优先优化对象，不代表已证明所有渲染路径没有瓶颈。', '',
    ]
    report[idx:idx] = findings
    idx = report.index('## 复现与原始证据')
    report[idx:idx] = [
        '## 实现与审阅', '',
        '- GameplayEngine 拆分阶段、聚合时间窗口并按原生单位注册监视器；EntityService、AnimalController 和三个物种 Controller 在现有函数中记录热点。',
        '- DebugService 记录调试绘制提交的 CPU 时间；HUD 刷新由 GameplayEngine 计时。显示开关仅由基准脚本配置。',
        '- RunBenchmark 与启动器加入采样档位、显示开关、版本化结果及秒级统计；PerformanceVerification 和 PerformanceGuide 同步更新。',
        '- [完整源码修改对照](changes.diff)、[当前源码校验和](source-hashes.json)。', '',
        '- 正式运行的 Profiler 日志包含新增局部变量 name 遮蔽 Node.name 的警告；正式测试后仅将这些局部变量和参数改名为 metric，并重跑 85 项性能验证、116 项模拟验证及 1 秒短 Profiler 检查，均通过。17 组性能数据未因纯改名而重复执行。',
        '- [改名后的短 Profiler 检查日志](warning-check-stderr.log) 仅剩未修改文件 RuntimeConfigPanel.gd:157 的三元表达式类型警告；保留原样，未纳入本次改动。', '',
    ]
    (HERE / 'report.md').write_text('\n'.join(report) + '\n', encoding='utf-8')
    summary = {label: {k: r.get(k) for k in ['average_fps', 'loop_hz', 'step_mean_ms', 'step_p95_ms', 'step_max_ms', 'simulation_wall_ratio', 'stages_mean_ms', 'hotspots', 'script_profiler_active']} for label, r in runs.items()}
    (HERE / 'summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    sources = list((ROOT / 'Scripts').rglob('*.gd')) + [ROOT / 'Tests' / name for name in ['RunBenchmark.gd', 'RunBenchmark.ps1', 'PerformanceVerification.gd']]
    (HERE / 'source-hashes.json').write_text(json.dumps({str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, indent=2), encoding='utf-8')
    print(json.dumps({label: {k: r.get(k) for k in ['average_fps', 'step_mean_ms', 'step_p95_ms', 'step_max_ms', 'script_profiler_active']} for label, r in runs.items()}, indent=2))


if __name__ == '__main__':
    main()
