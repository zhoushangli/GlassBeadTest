# 项目与修改边界
1. Godot 4.7 系列 2D 羊狼狗模拟；主场景 `Levels/Map/SCN_Root.tscn`，唯一业务 Autoload 为 `g_gameplayEngine`。
2. GameplayEngine 统一步进、时间和随机数；EntityService 持有唯一 AnimalData；GridService 构建步内快照；Systems 处理逻辑，Tasks 写运动意图，AnimalView 同步表现。
3. Packed 列共用 row；交换完整行并更新映射。长期引用校验 uid 与活动状态，结构变化后重新取得 row。羊沿用连续力，狼狗沿用行为树。
4. 先读代码；未明确授权修改时先讨论，已授权直接执行。保留用户已有修改，优先已有函数和结构，只改任务相关内容。
5. 保持现有目录、命名和类型标注；使用 Tab 缩进、snake_case、PascalCase、UPPER_SNAKE_CASE。分支体独立缩进，同一枚举或按键的多分支优先 match。
6. 不修改 addons 第三方代码；`.godot/` 为缓存，`output/` 为历史证据，均不作为当前源码整理。

# 空行与逻辑分段（重点）
1. 相邻函数之间恰好一行空行，包括 static 函数和内部类方法；函数前有说明注释时，空行放在注释之前，注释紧贴函数。函数体开头、结尾不额外留空行。
2. 函数内部按“小逻辑段”组织：准备输入、校验并提前返回、计算结果、提交状态、清理收尾等职责切换时，段间留一行空行。不出现连续两行空行。
3. 同一操作的相关语句连续书写，例如节点创建、属性设置、挂接父节点；同一字段组的赋值；一次查询及其直接校验。不要每条语句、每个变量或每个 if/for 前后机械加空行。
4. 提前返回或 continue 结束一组校验后，与后续实际处理空一行；同组连续校验保持紧凑。if/elif/else、match 分支和其所属代码保持连续，不用空行拆散同一控制结构。
5. 循环前的准备与循环可属于同一段；循环后开始另一项计算、另一个处理阶段或提交结果时空一行。简单计算及其直接 return 无需刻意拆段。
6. 声明靠近使用位置，保留初始化依赖和执行顺序：先取得配置、快照、节点或句柄，再声明依赖它们的值；不要为了集中声明或视觉对齐移动有副作用的调用、随机数、计时点、await 或生命周期操作。
7. 字段按职责分组，组间一行空行；同组字段紧凑。保留类型/常量、导出配置、节点引用、运行字段的现有组织及初始化依赖，不为排版重排初始化顺序。
8. 空行不含 Tab 或空格，行尾不留空白，文件末尾保留一个换行。格式整理只调整必要空白和注释，不夹带行为修改。

# 注释（重点）
1. 只写有助于理解步骤、实际效果、边界或单位的注释；简单赋值、明显分支、名称已表达清楚的代码不补凑数注释。沿用所在文件或已有注释段的语言，不批量翻译。
2. 流程类注释说明“这一步做什么”，使用 `# 1) Initialize state` 格式；同一流程按实际执行顺序编号为 `1)`、`2)`、`3)`，新的独立流程重新从 `1)` 开始。不要使用 `Step 1`、`1.` 或无编号标题代替步骤。
3. 流程注释放在对应逻辑段之前，与该段首行使用相同缩进并紧贴代码；与上一逻辑段空一行。只标注值得解释的阶段，不要求每个函数或每个分支都有编号。
4. 效果类注释必须恰好两行：第一行说明函数、字段或行为的实际效果，必要时写明单位、条件或生命周期；第二行以 `# e.g. ` 开头，给出与当前代码一致的具体调用、配置值或输入输出示例。
5. 效果注释两行缩进一致、连续书写，并紧贴被说明的声明或代码；示例必须体现第一行效果，不写占位 `...`、空泛描述或未经实现的承诺。
6. Godot Inspector/文档提示保留 `##`，同样遵循两行结构，第二行使用 `## e.g. ...`；不要改成普通 `#` 而丢失提示功能。其他语言使用对应注释符号，保留相同结构。

```gdscript
func update_state(settings: SimulationConfig) -> void:
	# 1) Validate the input before copying settings.
	if settings == null:
		return

	# 2) Copy settings and calculate the dependent population.
	var current := settings.copy_config()
	var counts := current.get_initial_counts()
	print(counts)

# Return the initial population after applying species ratios.
# e.g. get_initial_counts() returns Vector3i(240, 24, 12) with default settings.
func get_initial_counts() -> Vector3i:
	return g_gameplayEngine.config.get_initial_counts()
```

# 验证与交付
1. 构建前查看 `.vscode/tasks.json`（若存在），优先已有任务；Godot 源码为 `C:\Work\Godot\Editor\godot`，核对兼容版本，不为普通脚本修改重编引擎。
2. 脚本/场景/资源修改做相关解析或最小验证；纯文档/注释无需运行。测试入口为 `--headless --script res://Tests/RunWithAutoload.gd -- --entry=res://Tests/<脚本名>.gd`。
3. 按影响选择验证，不重复扩大已通过的检查；格式整理核对非空代码行及顺序未变。区分自动验证、运行观察与人工视觉验收，不以布局或截图证明性能或视觉通过。
4. 性能记录数量、时长、渲染及帧率上限；正常场景保留动物和 HUD，区分每步与每帧总耗时。证据写入 `output` 新目录。
5. 完成后简述文件、行为变化和验证结果；无法验证时说明原因及未验证范围。
