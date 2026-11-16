# 项目与入口
1. Godot 4.7 系列 2D 羊狼狗模拟；GDScript、LimboAI 行为树、自写 Packed SoA ECS。
2. 主场景 `Levels/Map/SCN_Root.tscn`；唯一业务 Autoload 为 `g_gameplayEngine`。
3. Autoload 场景为 `Prefabs/Runtime/Core/SCN_GameplayEngine.tscn`，不另建 ECS Autoload。
4. Godot 源码在 `C:\Work\Godot\Editor\godot`；查引擎行为时核对源码和运行版本。
5. 运行前检查 `.vscode/tasks.json`，存在则优先参考；不假定存在 C++/C# 构建流程。

# 职责与数据
1. GameplayEngine 负责固定阶段、统一时间、随机数、暂停单步、重置与配置应用。
2. EntityService 持有唯一 AnimalData，管理生成、slot/uid、生命周期与表现节点复用。
3. AnimalData 的 Packed 列共用 row，维护活动、尸体、复用区；交换完整行并更新映射。
4. AnimalEntity 仅保留生命句柄；长期引用校验 uid 与活动状态，结构变化后不得使用旧 row。
5. GridService 每个固定模拟步开始全量重建快照、成员与共享统计；使用扁平 Packed 数组。
6. 格子索引为 `cell.y * width + cell.x`；格子默认 30 px，可配置，修改需要重启。
7. Systems 批量处理逻辑，Tasks 写运动意图，AnimalView 关联句柄、重置树并同步表现。
8. 动物均使用现有行为树；不恢复 GECS、逐实体组件、Controller 或另建 FSM。
9. RootController 管场景和相机；DebugService/HUD 管选择与视觉，DebugPanel 管视觉开关。

# 行为与配置
1. 默认总数 276、羊狼狗相对比例 20:2:1，生成 240/24/12；没有草、饥饿、羊圈或实体碰撞。
2. 羊不使用 FOV；狼狗通过 Grid 查询附近羊，分别累加压力，羊消费结果并做局部分离。
3. 羊群聚合、对齐及狗保护中心使用格子统计；细致追逐、捕获仍计算具体个体。
4. 狼压力与狗压力分开，狼威胁标记独立于合力；羊行为优先逃跑、警戒、受驱赶、游走。
5. 狗保护局部羊群、收拢离群羊和追狼；保留距离/ID 认领，避免重复追赶。
6. 狼选择可见近羊，保留接近策略、冲刺捕获、狗威慑、失败反馈及猎捕后的休息。
7. 狼狗保留 FOV 与最多 3 秒最后可见位置搜索；不得读取隐藏目标实时位置来追逐。
8. 压力读取步开始快照；捕获、威慑和嚎叫范围保留移动后精算，嚎叫下一步影响羊。
9. 尸体和嚎叫表现使用模拟时间，暂停冻结、单步推进；视觉不得改变 RNG。
10. CFG 集中维护数值；动物颜色、形状和行为树引用保留在 Prefab。
11. 运行副本、UI 草稿和仓库默认 CFG 隔离；Apply 热应用普通参数并保留累计时间与反馈。
12. 种子、总数、物种比例、场地、格子大小显示 Apply & restart，保留暂停；重置清空记忆和认领。
13. Save applied 写 `user://CFG_Runtime.tres`；Load preset/Default CFG 仅填草稿，不覆盖仓库默认。
14. 新预设版本为 5；其他版本不自动转换，拒绝加载并保留原文件。
15. 新参数同步范围、跨字段校验、应用语义和提示；输入数字不得触发模拟快捷键。
16. F2 参数面板与 F3 Debug 面板互斥；F1 总开关默认关、默认仅选中，Esc 关闭不清选择。

# 修改与风格
1. 先读相关代码；未明确授权先讨论矛盾，已确认方案直接执行，不重复询问授权。
2. 不回滚用户已有修改；只改任务相关内容，不顺带修改 addons 第三方代码。
3. 优先已有函数和结构；非必要不新增类，不提前设计通用框架、多线程或 Compute Shader。
4. 保持 Scripts/Resources/Prefabs/Levels/Art/Tests 分工；场景资源保留无关属性和引用。
5. `.godot/` 是生成缓存；`output/` 是证据和历史副本，不当作当前源码。
6. 使用 Tab、snake_case、PascalCase、UPPER_SNAKE_CASE；控制语句体独立缩进，不写单行分支。
7. 函数之间只留一行空行；相关语句紧凑，小逻辑段间空一行，保留初始化依赖。
8. 类型和常量在前；导出配置、节点引用、运行字段分组，沿用现有类型标注和动态接口。
9. 同一枚举或按键多分支优先 match；条件检查与提前返回用 if，不强改简单判断。
10. 流程注释用 `# 1) Initialize state`；效果注释两行，第二行 `# e.g. ...`，沿用文件语言。
11. 不为简单代码堆注释；所有模拟逻辑沿用统一步进与 `g_gameplayEngine.rng`。

# 验证与沟通
1. 改脚本、场景或资源后做相关解析/最小验证；文档注释无需运行，不重编普通项目的引擎。
2. 使用兼容 Godot；入口 `--script res://Tests/RunWithAutoload.gd -- --entry=res://Tests/<脚本名>.gd`。
3. 无窗口加 `--headless`；优先 SimulationVerification、PerformanceVerification 的相关覆盖。
4. 公共机制改动覆盖动物与交互；完整回归用于阶段收尾或实际影响需要，不为低风险凑测试。
5. 测试各自准备最小数据，检查行为契约；同版通过后仅因新增修改、失败或具体疑点扩大验证。
6. DebugVisualVerification 的输入和截图不等于人工验收；自然流动、辨识和转向需运行观察。
7. 性能注明数量、时长、渲染、帧率上限；正常场景保留动物和 HUD，分别报告每步与每帧总耗时。
8. 不以 Packed 布局证明提速；区分设计、实现、自动验证与桌面验收，明确回归和未验证限制。
9. 证据写 output 新目录、不覆盖旧结果；结束简述改动、行为和验证，无法验证说明原因。
10. 讲解按“例子 → 新问题 → 影响 → 改动”逐步推进，先讲数据、表现与逻辑如何配合。
