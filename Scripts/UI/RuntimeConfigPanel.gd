class_name RuntimeConfigPanel
extends PanelContainer

const FIELD_HELP := {
	"Sheep.move_speed": "羊寻找食物时的移动速度，单位为像素/秒；闲逛速度还会乘以闲逛比例。\n例如：70 表示每秒最多移动 70 像素。",
	"Sheep.flee_speed": "羊逃离狼时的速度，单位为像素/秒。\n例如：110 表示逃跑时每秒最多移动 110 像素。",
	"Sheep.perception_radius": "羊在饥饿为 0 时的基础避险距离，也是扫描狼的最大距离；实际避险距离随饥饿百分比线性缩短，饥饿 100 时降至紧急距离。威胁判断和选草共用此距离。\n例如：基础 130、紧急 36 时，饥饿 50 对应避险距离 83 像素。",
	"Sheep.idle_speed_scale": "闲逛速度相对普通移动速度的比例。\n例如：0.5 表示以普通速度的一半闲逛。",
	"Sheep.flock_radius": "计算局部羊群中心时查找同伴的半径，单位为像素。\n例如：120 表示只参考附近 120 像素内的羊。",
	"Sheep.foraging_cohesion": "寻找食物途中靠近局部羊群中心的力度，接近草点后不再叠加。\n例如：0 表示寻找食物时不向同伴中心靠拢。",
	"Sheep.idle_cohesion": "闲逛时靠近局部羊群中心的力度。\n例如：数值越大，闲逛时越倾向于靠近附近同伴。",
	"Sheep.initial_hunger_min": "新生成羊的初始整数饥饿下限，范围为 0～100；修改不改变已有羊的饥饿值。\n例如：20 表示初始饥饿不低于 20。",
	"Sheep.initial_hunger_max": "新生成羊的初始整数饥饿上限，范围为 0～100；不得低于初始下限。\n例如：70 表示初始饥饿不高于 70。",
	"Sheep.hunger_per_second": "每模拟秒增加的整数饥饿点数，不足一点的增量累计保留，饥饿最多为 100。\n例如：1 表示每秒增加 1 点饥饿。",
	"Sheep.hungry_threshold": "饥饿达到此值后开始觅食，必须高于停止觅食阈值。\n例如：60 表示达到 60 点饥饿后开始找草。",
	"Sheep.full_threshold": "已经开始觅食的羊，饥饿降至此值或更低后停止觅食。\n例如：20 表示吃到饥饿不超过 20 时停止。",
	"Sheep.hunger_per_bite": "每完成一口草降低的整数饥饿点数，最低降至 0。\n例如：25 表示每口草减少 25 点饥饿。",
	"Sheep.grazing_duration": "完成一口草所需的连续模拟时间，单位为秒；离开吃草行为会重置进度。\n例如：2 表示连续吃草 2 秒才消耗一口。",
	"Sheep.grazing_distance": "羊与草点距离不超过此值时可以开始吃草，单位为像素。\n例如：18 表示进入草点周围 18 像素后可以吃草。",
	"Sheep.retarget_interval": "觅食时重新评估草目标的间隔，单位为秒；正在吃草时不因定时评估换目标。\n例如：1 表示每隔 1 秒考虑更好的草点。",
	"Sheep.retarget_improvement": "已有有效草目标时，新目标评分需要改善的比例；评分越低越好。\n例如：0.2 表示新目标至少改善 20% 才切换。",
	"Sheep.crowd_weight": "草点评分中其他羊预约数量的惩罚权重。\n例如：数值越大，越倾向选择预约较少的草点。",
	"Sheep.emergency_distance": "羊对任意狼的强制逃跑距离，单位为像素，也是饥饿 100 时的最小避险距离；不得超过基础避险距离。\n例如：36 表示狼进入 36 像素内时始终逃跑。",
	"Sheep.safety_duration": "狼离开实际避险范围后仍继续逃跑的模拟时间，单位为秒；减少此值可更快恢复觅食。\n例如：0.5 表示危险解除后继续逃跑半秒。",
	"Wolves.move_speed": "狼搜索猎物时的移动速度，单位为像素/秒。\n例如：70 表示搜索时每秒最多移动 70 像素。",
	"Wolves.chase_speed": "狼追赶和贴近猎物时的移动速度，单位为像素/秒。\n例如：135 表示追赶时每秒最多移动 135 像素。",
	"Wolves.retreat_speed": "狼逃离牧羊犬时的移动速度，单位为像素/秒。\n例如：160 表示避狗时每秒最多移动 160 像素。",
	"Wolves.perception_radius": "狼寻找羊和维持追赶的感知半径，单位为像素；猎物离开范围后放弃追赶。\n例如：260 表示只选择 260 像素内的羊。",
	"Wolves.dog_threat_distance": "牧羊犬对狼的威慑距离，单位为像素；狼发现狗进入此距离后放弃猎物并逃跑，捕获结算时也会检查。\n例如：90 表示狗进入狼周围 90 像素内即可打断猎捕。",
	"Wolves.search_interval": "没有可用猎物时重新搜索的间隔，单位为模拟秒；已有目标时保持追赶。\n例如：1 表示没有猎物时每秒搜索一次。",
	"Wolves.hunt_duration": "单次追赶允许持续的最长模拟时间，单位为秒；超时后重新选择，应用配置保留已追赶时间。\n例如：10 表示一次最多追赶 10 秒。",
	"Wolves.competition_weight": "其他狼已经追踪同一只羊时降低其选择权重，权重除以 1 加其他追踪狼数乘本值。\n例如：3 表示已有一只狼追踪时，选择权重降为原来的四分之一。",
	"Wolves.capture_distance": "狼可以累计捕获进度的最大距离，单位为像素；超过后进度清零。\n例如：22 表示必须持续贴近羊到 22 像素内。",
	"Wolves.capture_duration": "在捕获距离内连续维持多久才能捕获羊，单位为模拟秒；狗可以打断。\n例如：0.5 表示持续贴近半秒后捕获。",
	"Dogs.move_speed": "牧羊犬前往局部羊群守护点时的速度，单位为像素/秒。\n例如：80 表示守护移动时每秒最多移动 80 像素。",
	"Dogs.drive_speed": "牧羊犬拦截和驱赶狼时的速度，单位为像素/秒。\n例如：185 表示拦截和驱赶时每秒最多移动 185 像素。",
	"Dogs.return_speed": "牧羊犬返回守护点时的速度，单位为像素/秒。\n例如：100 表示返回时每秒最多移动 100 像素。",
	"Dogs.perception_radius": "牧羊犬能发现候选威胁狼的最大距离，单位为像素；实际威慑狼的距离由狼配置的 dog_threat_distance 控制。\n例如：240 表示狗只处理自己周围 240 像素内的狼。",
	"Dogs.local_flock_radius": "围绕保护锚点羊计算局部羊群中心的半径，单位为像素，也参与保护覆盖评分。\n例如：120 表示以锚点羊附近 120 像素内的羊计算中心。",
	"Dogs.protection_radius": "猎捕中或持续驱赶的狼距离保护中心不超过此半径时视为羊群威胁，还须在狗的感知范围内。\n例如：200 表示处理保护中心周围 200 像素内的猎捕威胁。",
	"Dogs.leash_distance": "牧羊犬离保护中心超过此距离后优先返回，单位为像素。\n例如：240 表示追离羊群超过 240 像素后返回。",
	"Dogs.guard_distance": "守护点相对局部羊群中心的偏移距离，单位为像素。\n例如：60 表示在羊群中心外约 60 像素处守护。",
	"Dogs.reassignment_interval": "重新评估保护锚点羊的间隔，单位为模拟秒；锚点死亡时立即重新选择。\n例如：2 表示每隔 2 秒重新评估保护对象。",
	"Dogs.reassignment_improvement": "已有保护锚点时，新锚点评分需要改善的比例；评分越低越好。\n例如：0.25 表示新锚点至少改善 25% 才更换。",
	"Dogs.coverage_weight": "选择保护锚点时，对其他狗已有覆盖的惩罚权重。\n例如：数值越大，越倾向保护其他狗较少覆盖的羊群。",
	"Grass.patch_radius": "每片草地的布局半径，单位为像素，也用于草目标距离评分；应用修改需要重启模拟。\n例如：84 表示草点分布在半径约 84 像素的草地中。",
	"Grass.per_patch": "每片草地包含的草点数量；应用修改需要重启模拟。\n例如：24 表示每片草地生成 24 个草点。",
	"Grass.bites": "每个草点可提供的口数，吃空后才开始恢复倒计时；应用修改需要重启模拟。\n例如：2 表示每个草点可被吃两口。",
	"Grass.regrow_duration": "草点吃空后原地恢复全部口数的模拟时间，单位为秒；修改只影响之后吃空的草点。\n例如：15 表示吃空后等待 15 秒恢复。",
	"World.random_seed": "统一模拟随机种子；相同配置和操作顺序可重现随机结果，应用修改需要重启。\n例如：1337 表示使用固定种子 1337。",
	"World.initial_sheep": "模拟开始时的羊数量；应用修改需要重启模拟并保留暂停状态。\n例如：240 表示初始生成 240 只羊。",
	"World.initial_wolves": "模拟开始时的狼数量；应用修改需要重启模拟并保留暂停状态。\n例如：24 表示初始生成 24 只狼。",
	"World.initial_sheepdogs": "模拟开始时的牧羊犬数量；应用修改需要重启模拟并保留暂停状态。\n例如：12 表示初始生成 12 只牧羊犬。",
	"World.perception_interval": "动物采样附近实体和软分离的间隔，单位为模拟秒；不是全部 AI 决策的更新间隔。\n例如：0.125 表示约每 0.125 秒更新一次邻居采样。",
	"World.separation_distance": "同物种动物之间软分离的作用距离，单位为像素；不等同于物理碰撞。\n例如：24 表示同类靠近到 24 像素内时产生分离移动。",
	"World.death_duration": "动物死亡后保留表现多久再移除，单位为模拟秒。\n例如：0.3 表示死亡表现保留 0.3 秒。",
}

@onready var tabs: TabContainer = $Margin/Column/Tabs
@onready var message: Label = $Margin/Column/Message
@onready var apply_button: Button = $Margin/Column/Actions/Apply
@onready var pause_button: Button = $Margin/Column/Header/Pause

var gameplay_engine: Node
var draft: SimulationConfig
var editors: Dictionary[String, SpinBox] = {}

func _ready() -> void:
	$Margin/Column/Header/Close.pressed.connect(close)
	pause_button.pressed.connect(_toggle_pause)
	apply_button.pressed.connect(_apply)
	$Margin/Column/Actions/Defaults.pressed.connect(_restore_defaults)
	$Margin/Column/Presets/Save.pressed.connect(_save)
	$Margin/Column/Presets/Load.pressed.connect(_load)

func initialize(engine: Node) -> void:
	gameplay_engine = engine
	if not engine.configuration_applied.is_connected(_on_applied):
		engine.configuration_applied.connect(_on_applied)
	set_draft(engine.config)

func toggle() -> void:
	if visible:
		close()
	else:
		set_draft(gameplay_engine.config)
		show()

func close() -> void:
	hide()
	get_viewport().gui_release_focus()

func set_draft(settings: SimulationConfig) -> void:
	draft = settings.copy_config()
	var selected_tab := maxi(0, tabs.current_tab)
	for child in tabs.get_children():
		tabs.remove_child(child)
		child.queue_free()
	editors.clear()

	for section_name: String in draft.get_sections():
		var section: Resource = draft.get_sections()[section_name]
		var scroll := ScrollContainer.new()
		scroll.name = section_name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_theme_constant_override("separation", 7)
		scroll.add_child(rows)

		var group_name: String = ""
		for property in section.get_property_list():
			if (property.usage & PROPERTY_USAGE_GROUP) != 0:
				group_name = property.name
				continue
			if (property.usage & PROPERTY_USAGE_EDITOR) == 0 or property.hint != PROPERTY_HINT_RANGE:
				continue
			if not group_name.is_empty():
				var heading := Label.new()
				heading.text = group_name
				heading.add_theme_color_override("font_color", Color("#b8d94b"))
				heading.add_theme_font_size_override("font_size", 14)
				rows.add_child(heading)
				group_name = ""
			_add_editor(rows, section_name, section, property)

	tabs.current_tab = mini(selected_tab, tabs.get_tab_count() - 1)
	_update_apply_state()
	refresh()

func _add_editor(rows: VBoxContainer, section_name: String, section: Resource, property: Dictionary) -> void:
	var row := HBoxContainer.new()
	rows.add_child(row)
	var label := Label.new()
	label.text = str(property.name).capitalize()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	label.tooltip_text = FIELD_HELP.get(section_name + "." + str(property.name), label.text)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.name = property.name
	spin.custom_minimum_size = Vector2(124, 30)
	var limits: PackedStringArray = property.hint_string.split(",")
	spin.min_value = limits[0].to_float()
	spin.max_value = limits[1].to_float()
	spin.step = limits[2].to_float() if limits.size() > 2 else 1.0
	spin.set_value_no_signal(float(section.get(property.name)))
	spin.tooltip_text = label.tooltip_text
	row.add_child(spin)
	editors[section_name + "." + str(property.name)] = spin
	spin.value_changed.connect(_value_changed.bind(section_name, property.name, property.type))

func _value_changed(value: float, section_name: String, property_name: StringName, value_type: int) -> void:
	var section: Resource = draft.get_sections()[section_name]
	section.set(property_name, int(value) if value_type == TYPE_INT else value)
	_update_apply_state()

func _update_apply_state() -> void:
	var error := draft.validate()
	apply_button.disabled = not error.is_empty()
	var restart := draft.requires_restart(gameplay_engine.config)
	apply_button.text = "Apply & restart" if restart else "Apply"
	if not error.is_empty():
		message.text = error
	elif restart:
		message.text = "Population, seed or grass layout changed. Apply restarts the simulation."
	else:
		message.text = "Apply updates current animals. Running cooldowns keep their sampled duration."

func _apply() -> void:
	# 1) Commit text fields before validating the complete draft.
	for spin in editors.values():
		spin.apply()
	var error: String = gameplay_engine.request_config_apply(draft)
	if error.is_empty():
		message.text = "Applying..."
		apply_button.disabled = true
		get_viewport().gui_release_focus()
	else:
		message.text = error

func _on_applied(restarted: bool) -> void:
	set_draft(gameplay_engine.config)
	message.text = "Applied and restarted. Pause state preserved." if restarted else "Applied to current and newly spawned animals."

func _restore_defaults() -> void:
	set_draft(gameplay_engine.defaults)
	message.text = "Default CFG values loaded into the form. Apply when ready."

func _save() -> void:
	var result: Error = gameplay_engine.save_preset()
	message.text = "Applied settings saved to CFG_Runtime.tres." if result == OK else "Could not save preset: " + error_string(result)

func _load() -> void:
	var loaded: SimulationConfig = gameplay_engine.load_preset()
	if loaded == null:
		message.text = "Preset missing or incompatible. Hunger values must use integer points (0-100); old normalized presets are unsupported."
		return
	set_draft(loaded)
	message.text = "Saved preset loaded into the form. Apply when ready."

func _toggle_pause() -> void:
	gameplay_engine.paused = not gameplay_engine.paused
	get_viewport().gui_release_focus()
	refresh()

func refresh() -> void:
	if is_instance_valid(gameplay_engine):
		pause_button.text = "Resume" if gameplay_engine.paused else "Pause"
