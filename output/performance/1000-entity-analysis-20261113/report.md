# 初始 1000 Entity 性能分析报告

原场地三次桌面基线的平均 FPS 中位数为 **1.85**，每模拟步平均耗时中位数为 **66.96 ms**。当前距离 60 FPS／60 Hz 实时模拟的预算（每帧约 16.67 ms）有明显差距。

在代表性基线 `fixed-stages-1` 中，最耗时阶段为 **Perception，47.69 ms／步（71.2%）**。纯移动为 **1.83 ms／步**。瓶颈排序以本文的阶段、热点及 Profiler 证据为依据。

详细档中，前三个已测热点为：**DogAnchor：10.91 ms／步**；**NeighborScan：7.41 ms／步**；**WolfTarget：7.34 ms／步**。此排序仅覆盖已布置的热点；其余感知逻辑仍需结合 Profiler 分析。

## 测试环境与口径

- 引擎：4.7.2-stable (official)；LimboAI 元数据和二进制 SHA-256 随每份 JSON 保存。
- CPU：Intel(R) Core(TM) Ultra 9 275HX；GPU：NVIDIA GeForce RTX 5070 Ti Laptop GPU；渲染器：gl_compatibility。
- 初始 870 羊、87 狼、43 狗；草点和节点不计入动物总数。固定种子 1337，初始动物位置均匀分布，采用既有 uniform_v1 布局。
- 每次预热 5 秒墙钟，再测量至少 60 秒墙钟；串行启动，外部超时 120 秒。1280×720 视口，模拟 60 Hz；除 cap60 外均取消 FPS 上限，关闭 VSync。
- 原场地 1280×720；scaled 同比扩大面积与草量，并把全场缩放到同一视口。因此 scaled 同时改变局部密度、草搜索工作量和显示比例，不能视为只改变一项变量。
- 60 秒是实际经过时间，模拟可能推进不足 60 秒。捕获不被禁止，也不补充动物；预热结束时已可能少于 1000。每秒记录种群和模拟进度。
- 运行时保留原有用户编辑器进程，未主动结束用户进程；测试不连接远程 Profiler。系统其他后台负载未隔离。
- 基线采用阶段采样；off 用于观察采样开销；detailed 和 profiler 仅用于诊断。没有重新编译 Godot，没有修改默认 CFG 或行为规则。

这些结果来自当前编辑器发行包运行项目，不能当作导出 Release 包的性能结论。

## 全部运行结果

表中时间均为毫秒，种群按羊／狼／狗排列；headless 行的第二列是循环 Hz，其余行为桌面 FPS。Frame P95 包括整次循环中的模拟、渲染与等待，不等于 GPU 时间。

| 运行／原始结果 | FPS／Hz | Frame P95 | Step mean | Step P95 | Step max | 模拟／墙钟 | 测量开始 → 结束 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [fixed-stages-1](../2026-11-13T15-47-25_fixed-stages-1_380792_2486288/result.json) | 1.85 | 1631.50 | 66.96 | 80.95 | 1496.42 | 0.247 | 868/87/43 → 799/87/43 |
| [scaled-stages-1](../2026-11-13T15-48-33_scaled-stages-1_282180_1677353/result.json) | 2.30 | 1487.30 | 53.69 | 58.35 | 1427.88 | 0.306 | 860/87/43 → 651/87/43 |
| [fixed-stages-2](../2026-11-13T15-49-41_fixed-stages-2_242440_1859649/result.json) | 1.86 | 1645.26 | 66.64 | 74.96 | 1576.88 | 0.248 | 864/87/43 → 796/87/43 |
| [scaled-stages-2](../2026-11-13T15-50-50_scaled-stages-2_71008_1778651/result.json) | 2.26 | 1388.22 | 54.63 | 59.78 | 1682.99 | 0.301 | 860/87/43 → 654/87/43 |
| [fixed-stages-3](../2026-11-13T15-51-58_fixed-stages-3_71960_1875278/result.json) | 1.64 | 1910.79 | 75.30 | 91.08 | 1603.61 | 0.218 | 868/87/43 → 806/87/43 |
| [scaled-stages-3](../2026-11-13T15-53-06_scaled-stages-3_122456_1756725/result.json) | 2.01 | 1707.08 | 61.74 | 74.24 | 1960.60 | 0.268 | 862/87/43 → 685/87/43 |
| [fixed-off](../2026-11-13T15-54-14_fixed-off_263604_1631181/result.json) | 1.72 | 1627.64 | 72.18 | 87.90 | 2007.03 | 0.230 | 868/87/43 → 806/87/43 |
| [fixed-detailed](../2026-11-13T15-55-23_fixed-detailed_67028_1860187/result.json) | 1.80 | 1664.35 | 68.67 | 84.58 | 1478.39 | 0.240 | 868/87/43 → 804/87/43 |
| [fixed-headless](../2026-11-13T15-56-30_fixed-headless_293744_503687/result.json) | 1.27 | 2482.10 | 97.82 | 110.79 | 2161.84 | 0.170 | 868/87/43 → 816/87/43 |
| [fixed-no-debug](../2026-11-13T15-57-38_fixed-no-debug_124272_2173280/result.json) | 1.73 | 1781.92 | 71.71 | 84.76 | 1746.57 | 0.230 | 868/87/43 → 806/87/43 |
| [fixed-lines](../2026-11-13T15-58-46_fixed-lines_212428_2061963/result.json) | 1.78 | 1666.42 | 69.29 | 85.21 | 1749.56 | 0.237 | 868/87/43 → 804/87/43 |
| [fixed-hide-animals](../2026-11-13T15-59-55_fixed-hide-animals_114956_1998529/result.json) | 1.71 | 1739.65 | 72.62 | 93.37 | 1485.84 | 0.228 | 868/87/43 → 806/87/43 |
| [fixed-hide-grass](../2026-11-13T16-01-03_fixed-hide-grass_256112_2196635/result.json) | 1.64 | 2023.16 | 75.80 | 90.48 | 1806.10 | 0.218 | 868/87/43 → 806/87/43 |
| [fixed-hide-both](../2026-11-13T16-02-13_fixed-hide-both_113836_2192766/result.json) | 1.77 | 1718.45 | 70.35 | 88.64 | 1626.89 | 0.235 | 868/87/43 → 804/87/43 |
| [fixed-cap60](../2026-11-13T16-03-21_fixed-cap60_233436_1986229/result.json) | 1.72 | 1734.49 | 72.19 | 86.96 | 2010.01 | 0.229 | 868/87/43 → 806/87/43 |
| [fixed-profiler](../2026-11-13T16-04-30_fixed-profiler_355120_1823058/result.json) | 1.25 | 2448.15 | 98.76 | 117.40 | 2769.35 | 0.167 | 869/87/43 → 816/87/43 |
| [fixed-closing](../2026-11-13T16-06-00_fixed-closing_282588_1833281/result.json) | 1.72 | 1752.07 | 72.17 | 87.25 | 1650.79 | 0.229 | 868/87/43 → 806/87/43 |

原场地三次平均 FPS 范围：1.64～1.86；scaled 三次平均 FPS 中位数：2.26，每步平均耗时中位数：54.63 ms。

## 模拟阶段与热点

阶段表采用每步平均耗时居中的基线 `fixed-stages-1`；各阶段互斥。Preparation 合计草更新及预约统计；Cleanup 包含过期移除和模拟时钟、步数更新。

| 阶段 | 平均 ms／步 | 占总步进 |
| --- | --- | --- |
| Perception | 47.693 | 71.2% |
| HuntUpdate | 8.618 | 12.9% |
| Decision | 7.487 | 11.2% |
| Movement | 1.826 | 2.7% |
| SpatialBuild | 0.731 | 1.1% |
| Interaction | 0.356 | 0.5% |
| Preparation | 0.154 | 0.2% |
| Cleanup | 0.094 | 0.1% |

阶段总和与总步进之差为 0.000000000 ms（浮点舍入误差）。总步进边界不包含窗口聚合、Benchmark 信号回调、HUD 或绘制；因此阶段占比不能当作完整帧占比。

详细采样的热点表：耗时包含函数下层调用；每步指该步所有调用累计后再求平均，单次指总耗时除调用次数。热点属于上面的阶段内部，不能重复相加。

| 热点 | 总调用数 | 平均 ms／步 | 平均 ms／次 | 累计 ms |
| --- | --- | --- | --- | --- |
| DogAnchor | 305 | 10.907 | 31.1837 | 9511.03 |
| NeighborScan | 104417 | 7.410 | 0.0619 | 6461.87 |
| WolfTarget | 1762 | 7.342 | 3.6333 | 6401.89 |
| Separation | 104417 | 4.803 | 0.0401 | 4187.89 |
| SheepGrass | 4505 | 3.648 | 0.7062 | 3181.21 |
| NearbyQuery | 536163 | 2.323 | 0.0038 | 2025.75 |

详细档最慢的四个采样窗口如下。狗选目标的累计耗时集中在模拟时间约 4、8、12、14 秒附近，与 2 秒重分配周期对应，是长停顿的重要直接证据；这是窗口累计，不把它误称为单次函数或单个模拟步耗时。

| 墙钟窗口结束 s | 模拟时间 s | 窗口步数 | Step mean ms | 狗重分配次数 | 狗重分配累计 ms |
| --- | --- | --- | --- | --- | --- |
| 47.12 | 12.12 | 8 | 225.12 | 41 | 1422.13 |
| 29.27 | 8.12 | 8 | 204.16 | 41 | 1201.08 |
| 56.41 | 14.25 | 16 | 145.59 | 40 | 1391.18 |
| 13.62 | 4.12 | 16 | 128.85 | 42 | 1197.23 |

即使仅在详细档账面上扣除 DogAnchor 的全部平均耗时，剩余仍为 57.77 ms／步，明显超过 16.67 ms。这个算式不是优化收益预测，而是说明只解决重分配尖峰仍不足以达到实时目标，常态感知、狼选目标与决策成本也必须继续降低。

空间工作量（详细档）：每步查询 614.9 次，每次平均候选 68.9 个，单次最大候选 623 个，单格最大占用 77 只。候选尚未做圆形距离和物种筛选。

源码对应关系与优化建议：

- 狗选保护对象对每只羊计算评分，评分内再次遍历狗；当前 CFG 每 2 秒模拟时间重新分配，初始计时也一致，容易同一步集中执行。优先用热点和 Profiler 判断其对长步进的贡献；之后可讨论分散重分配时刻、复用覆盖统计。
- 狼选猎物先遍历羊，再为候选羊遍历狼计算竞争权重。可讨论共享追踪计数、用空间候选缩小选猎物范围，须保留当前加权选择语义。
- 邻居扫描和软分离重复遍历候选；应先区分返回候选的成本与候选过滤、向量运算成本，再考虑复用遍历或调整查询范围。
- 羊选草遍历所有草点，部分评分改进候选还遍历狼；饥饿与草量变化会改变此成本。可讨论草候选筛选及安全检查复用，不能只根据早期短样本排除它。
- 本次不实施上述优化，不引入 ECS、多线程、Compute Shader 或新服务框架。

## 时间段、显示和测量开销

以下按墙钟区间汇总；Step mean 按实际模拟步数加权，不能直接比较不同模拟进度的行为强度。

| 运行 | 墙钟区间 | 样本模拟时间 | 样本存活数 | Step mean ms | 最耗时阶段 |
| --- | --- | --- | --- | --- | --- |
| fixed-stages-1 | 0～20 s | 1.32～5.58 s | 994 → 971 | 68.51 | Perception |
| fixed-stages-1 | 20～40 s | 5.98～10.38 s | 966 → 946 | 69.64 | Perception |
| fixed-stages-1 | 40～60 s | 10.78～15.85 s | 946 → 929 | 63.31 | Perception |
| fixed-detailed | 0～20 s | 1.32～5.72 s | 994 → 970 | 64.84 | Perception |
| fixed-detailed | 20～40 s | 6.12～10.38 s | 964 → 946 | 72.48 | Perception |
| fixed-detailed | 40～60 s | 10.65～15.45 s | 946 → 934 | 68.80 | Perception |

| 对照 | 平均 FPS | 相对基线中位数 | Step mean 差 ms | 每秒采样 draw calls 平均 |
| --- | --- | --- | --- | --- |
| fixed-off | 1.72 | -6.8% | 5.22 | 500.64 |
| fixed-detailed | 1.80 | -2.5% | 1.72 | 620.93 |
| fixed-no-debug | 1.73 | -6.6% | 4.75 | 612.48 |
| fixed-lines | 1.78 | -3.8% | 2.33 | 619.67 |
| fixed-hide-animals | 1.71 | -7.5% | 5.67 | 128.74 |
| fixed-hide-grass | 1.64 | -11.6% | 8.84 | 500.76 |
| fixed-hide-both | 1.77 | -4.5% | 3.40 | 10.00 |
| fixed-cap60 | 1.72 | -7.2% | 5.23 | 619.41 |
| fixed-closing | 1.72 | -7.1% | 5.22 | 623.46 |

为检查运行期间的波动，末尾补测相同桌面基线：1.72 FPS、72.17 ms／步；相对前三次基线中位数，步耗时变化 +7.8%。这是额外控制组，未纳入最初三次基线中位数。

headless 的单步平均为 97.82 ms，反而比桌面基线慢。本轮未控制 CPU 亲和性、运行模式调度和热状态，因此不把这一差值解释为渲染成本。

各对照只测一次，帧率差受系统负载、热状态、模拟进度及种群变化影响，不能把小幅差异当成确定收益。关闭采样也保留既有总步进计时和 Benchmark 采集，故 off 表示关闭新增的阶段／空间／热点监视，不表示零测量开销。

| 运行 | HUD ms／刷新 | 调试绘制 CPU ms／调用 |
| --- | --- | --- |
| fixed-stages-1 | 0.1573 | 0.0011 |
| fixed-no-debug | 0.0000 | 0.0000 |
| fixed-lines | 0.1766 | 0.4075 |

原场景使用 Sprite2D、Polygon2D 表现。隐藏动物或草仍保留其模拟与节点；测量差值是整体显示影响，不能精确分解为 GPU 时间。Compatibility 路径本轮未采集可靠 GPU 时间，因此 JSON 明确标记 gpu_timing_available=false。

## Profiler 与验证限制

- 单独 Profiler 运行的 scripts profiling 状态：`True`。原始函数排行保存在该运行的 stdout.log；其帧率不作为基线。
- 代表性基线实际记录 888 个模拟步和 111 次渲染循环，平均每循环 8.00 步。固定步长补步使低 FPS 下每帧执行多次模拟步；不能把 1 / StepMean 直接当成实际 FPS。
- 解析／导入通过；PerformanceVerification 85 项、SimulationVerification 116 项通过。验证覆盖原生时间类型注册、秒转换、阶段求和、暂停零窗口、重置／停止清理，以及 off／stages／detailed 固定步数的随机数和动物状态一致性。
- 编辑器 UI 目视验收未完成：Computer Use 应用访问批准等待超时。已验证回调秒值和 MONITOR_TYPE_TIME 类型；尚未目视确认实际列表与曲线的 ms 排版。
- 本地 Godot 源码为 4.8 beta，测试使用 4.7.2 stable；未将不同版本源码的能力当作运行验证。
- 本轮测量从预热后开始，不覆盖最初创建 1000 只动物、导入资源及首次完整感知的启动尖峰。

- 基准使用均匀初始布局；普通场景的 spawn_initial 会把羊集中生成在中央区域，因此不能把本结果视为所有初始聚集布局的上限。

- 代表性基线在测量期间只推进 14.80 秒模拟时间；本报告不覆盖长时间草耗尽、持续饥饿及生态演化后的性能。

Profiler 的退出 ACCUMULATED 表为空，因此改用日志中实际输出的 **43 个 FRAME 函数快照**。以下按采样帧 Self 总和排序；Self 中位数与峰值按采样帧统计，Calls 只累计这些快照。快照含启动及预热，未覆盖所有帧，不能当作全程累计或与 60 秒阶段表相加。

| 函数 | 样本 Inclusive s | 样本 Self s | Self 中位数 ms／采样帧 | Self 最大 ms／采样帧 | 样本 Calls |
| --- | --- | --- | --- | --- | --- |
| res://Scripts/SheepController.gd::58::SheepController.perceive | 13.044 | 6.823 | 155.912 | 287.929 | 287939 |
| res://Scripts/SheepdogController.gd::78::SheepdogController._anchor_score | 12.622 | 6.415 | 0.000 | 1356.969 | 213186 |
| res://Scripts/AnimalController.gd::109::AnimalController.decide | 3.224 | 3.078 | 70.508 | 90.004 | 332529 |
| res://Scripts/SheepController.gd::40::SheepController._scan_neighbors | 3.269 | 2.841 | 64.721 | 127.970 | 36796 |
| res://Scripts/WolfController.gd::51::WolfController._prey_weight | 2.513 | 2.512 | 51.708 | 125.422 | 119175 |
| res://Scripts/SheepdogController.gd::26::SheepdogController.perceive | 17.333 | 2.372 | 53.126 | 85.760 | 14749 |
| res://Scripts/AnimalController.gd::85::AnimalController._scan_separation | 2.046 | 2.046 | 46.690 | 91.793 | 42490 |
| res://Scripts/AnimalController.gd::60::AnimalController.is_live | 2.029 | 2.029 | 9.073 | 347.967 | 11223210 |
| res://Scripts/SheepController.gd::121::SheepController._grass_unsafe | 3.126 | 1.659 | 38.101 | 83.356 | 72821 |
| res://Scripts/Core/EntityService.gd::112::EntityService.get_nearby_indices | 0.992 | 0.888 | 20.294 | 40.131 | 222922 |
| res://Scripts/SheepController.gd::91::SheepController._update_threat | 2.149 | 0.840 | 19.502 | 25.550 | 287939 |
| res://Scripts/SheepdogController.gd::104::SheepdogController._update_protection_center | 0.861 | 0.734 | 16.576 | 22.966 | 14749 |

## 证据支持的优化优先级

1. **先处理狗重分配尖峰。** 详细档每次选择约 31 ms，多个狗集中触发产生约 1.2～1.4 秒的窗口累计开销；Profiler 也直接记录到 _anchor_score 的单个采样帧 Self 峰值约 1.36 秒。应先讨论分散重分配时刻及减少重复覆盖评分。
2. **细分羊的常态感知。** Profiler 样本中 SheepController.perceive 的 Self 总和最高，除子脚本调用外仍有明显开销。源码包含每步状态与饥饿维护、黑板写入和草安全判断；Self 也可能包含原生调用成本，当前不能把它全部归到某一行或 LimboAI 内部。_grass_unsafe 还会在选草之外被调用，不能只看 SheepGrass 热点就排除其成本。
3. **减少候选后的重复处理及狼竞争评分。** 邻居扫描、软分离与 _prey_weight 均有函数级证据。先减少重复遍历和评分工作，再根据候选数量评估网格参数；仅改空间网格不足以解释或消除当前大部分耗时。
4. **移动、HUD 与渲染调整排在上述模拟问题之后。** 纯移动约占基线步进的 2.7%；隐藏动物与草、关闭调试均未带来超出波动范围的改善。这说明它们目前不是优先优化对象，不代表已证明所有渲染路径没有瓶颈。

## 实现与审阅

- GameplayEngine 拆分阶段、聚合时间窗口并按原生单位注册监视器；EntityService、AnimalController 和三个物种 Controller 在现有函数中记录热点。
- DebugService 记录调试绘制提交的 CPU 时间；HUD 刷新由 GameplayEngine 计时。显示开关仅由基准脚本配置。
- RunBenchmark 与启动器加入采样档位、显示开关、版本化结果及秒级统计；PerformanceVerification 和 PerformanceGuide 同步更新。
- [完整源码修改对照](changes.diff)、[当前源码校验和](source-hashes.json)。

- 正式运行的 Profiler 日志包含新增局部变量 name 遮蔽 Node.name 的警告；正式测试后仅将这些局部变量和参数改名为 metric，并重跑 85 项性能验证、116 项模拟验证及 1 秒短 Profiler 检查，均通过。17 组性能数据未因纯改名而重复执行。
- [改名后的短 Profiler 检查日志](warning-check-stderr.log) 仅剩未修改文件 RuntimeConfigPanel.gd:157 的三元表达式类型警告；保留原样，未纳入本次改动。

## 复现与原始证据

- [运行清单及启动日志路径](manifest.json)、[串行测试脚本](run-suite.ps1)、[报告生成脚本](summarize.py)。
- [性能验证日志](verification.log)、[模拟验证日志](simulation-verification.log)、[导入日志](import.log)。
- 使用项目 Tests/RunBenchmark.ps1；示例：`./Tests/RunBenchmark.ps1 -Entities 1000 -Scenario fixed -Sampling detailed -Warmup 5 -Duration 60 -TimeoutSeconds 120 -Label manual-detailed`。
- 阶段／热点监视器的值保持数值；时间回调返回秒，编辑器显示 ms；JSON 的 `_ms` 字段仍为毫秒。旧合并字段含义保持不变，新增字段提供独立阶段。
