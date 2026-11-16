class_name RuntimeConfigPanel
extends PanelContainer

const FIELD_HELP := {
	"Sheep.move_speed": "常态移动速度（px/s）。\n例如：move_speed = 70.0。",
	"Sheep.flee_speed": "逃跑速度（px/s）。\n例如：flee_speed = 110.0。",
	"Sheep.idle_speed_scale": "游走速度比例。\n例如：idle_speed_scale = 0.5。",
	"Sheep.wolf_pressure_distance": "全向狼压力距离（px）。\n例如：wolf_pressure_distance = 130.0。",
	"World.grid_cell_size": "Grid 格子边长（px），修改需要重启；小格子降低候选数量但增加统计工作。\n例如：grid_cell_size = 30。",
	"Sheep.hunting_pressure_multiplier": "追猎狼的局部压力倍率；可热应用。\n例如：hunting_pressure_multiplier = 2.0。",
	"Sheep.wander_weight": "游走作用的权重，随危险强度降低。\n例如：wander_weight = 0.35。",
	"Sheep.panic_duration": "恐慌强度线性衰减至零的时间（模拟秒）；0 立即清零。\n例如：panic_duration = 2.0。",
	"Sheep.flock_radius": "局部聚合半径（px）。\n例如：flock_radius = 55.0。",
	"Sheep.alignment_radius": "速度对齐半径（px）。\n例如：alignment_radius = 45.0。",
	"Sheep.separation_weight": "软分离权重。\n例如：separation_weight = 2.8。",
	"Sheep.alignment_weight": "速度对齐权重。\n例如：alignment_weight = 0.4。",
	"Sheep.cohesion_weight": "局部聚合权重。\n例如：cohesion_weight = 0.25。",
	"Sheep.herding_distance": "全向避狗压力距离（px）。\n例如：herding_distance = 90.0。",
	"Sheep.dog_pressure_weight": "避狗压力权重。\n例如：dog_pressure_weight = 1.4。",
	"Sheep.wolf_pressure_weight": "远离狼或恐慌源的权重。\n例如：wolf_pressure_weight = 4.0。",
	"Sheep.steering_rate": "速度趋近目标的响应率（每秒）。\n例如：steering_rate = 4.0。",
	"Wolves.move_speed": "常态移动速度（px/s）。\n例如：move_speed = 70.0。",
	"Wolves.chase_speed": "冲刺速度（px/s）。\n例如：chase_speed = 135.0。",
	"Wolves.retreat_speed": "避狗撤退速度（px/s）。\n例如：retreat_speed = 160.0。",
	"Wolves.patrol_speed_scale": "巡逻速度比例。\n例如：patrol_speed_scale = 0.6。",
	"Wolves.perception_radius": "视觉距离（px）。\n例如：perception_radius = 260.0。",
	"Wolves.vision_angle": "完整扇形角度（度）。\n例如：vision_angle = 130.0。",
	"Wolves.memory_duration": "最后可见位置的记忆时间（秒）。\n例如：memory_duration = 3.0。",
	"Wolves.dog_threat_distance": "狗触发全向撤退的距离（px）。\n例如：dog_threat_distance = 90.0。",
	"Wolves.hunt_duration": "单次猎捕总时限（秒）。\n例如：hunt_duration = 10.0。",
	"Wolves.rest_duration": "猎捕或撤退后的休息时间（秒）。\n例如：rest_duration = 3.0。",
	"Wolves.capture_distance": "冲刺即时捕获距离（px）。\n例如：capture_distance = 22.0。",
	"Wolves.charge_distance_scale": "冲刺触发距离相对捕获距离的倍数。\n例如：charge_distance_scale = 4.0。",
	"Wolves.strategy_offset": "侧面或后方接近偏移（px）。\n例如：strategy_offset = 40.0。",
	"Wolves.strategy_decay": "每秒减少的策略失败计数。\n例如：strategy_decay = 0.05。",
	"Wolves.howl_radius": "嚎叫刺激半径（px）。\n例如：howl_radius = 200.0。",
	"Wolves.howl_trigger_distance": "可见猎物触发嚎叫的距离（px）。\n例如：howl_trigger_distance = 200.0。",
	"Wolves.howl_cooldown": "嚎叫冷却时间（秒）。\n例如：howl_cooldown = 5.0。",
	"Dogs.move_speed": "常态移动速度（px/s）。\n例如：move_speed = 80.0。",
	"Dogs.drive_speed": "驱狼速度（px/s）。\n例如：drive_speed = 185.0。",
	"Dogs.return_speed": "返回速度（px/s）。\n例如：return_speed = 100.0。",
	"Dogs.perception_radius": "视觉距离（px）。\n例如：perception_radius = 240.0。",
	"Dogs.vision_angle": "完整扇形角度（度）。\n例如：vision_angle = 120.0。",
	"Dogs.memory_duration": "最后可见位置的记忆时间（秒）。\n例如：memory_duration = 3.0。",
	"Dogs.local_flock_radius": "保护锚点附近的局部羊群半径（px）。\n例如：local_flock_radius = 120.0。",
	"Dogs.threat_distance": "狼靠近受保护羊的威胁距离（px）。\n例如：threat_distance = 180.0。",
	"Dogs.leash_distance": "超出局部中心后优先返回的距离（px）。\n例如：leash_distance = 240.0。",
	"Dogs.guard_distance": "巡逻圆半径（px）。\n例如：guard_distance = 120.0。",
	"Dogs.patrol_angular_speed": "巡逻角速度（rad/s）。\n例如：patrol_angular_speed = 0.6。",
	"Dogs.collect_distance": "收拢时位于离群羊外侧的距离（px）。\n例如：collect_distance = 75.0。",
	"Dogs.collect_complete_ratio": "收拢完成距离相对局部半径的比例。\n例如：collect_complete_ratio = 0.8。",
	"Dogs.reassignment_interval": "重新评估保护锚点的间隔（秒）。\n例如：reassignment_interval = 2.0。",
	"Dogs.reassignment_improvement": "更换有效锚点所需的评分改善比例。\n例如：reassignment_improvement = 0.25。",
	"Dogs.coverage_weight": "其他狗已覆盖附近羊时的惩罚权重。\n例如：coverage_weight = 2.0。",
	"World.random_seed": "统一模拟随机种子；相同配置和操作顺序可重现随机结果，应用修改需要重启。\n例如：1337 表示使用固定种子 1337。",
	"World.initial_total": "初始实体总数；修改需要重启并保留暂停。取整后各物种数量之和始终等于总数。\n例如：276 配合 20:2:1 生成 240 羊、24 狼、12 狗。",
	"World.sheep_ratio": "羊的相对比例，与狼狗比例自动归一化，不要求总和为 100；0 表示不生成羊，修改需要重启。\n例如：20:2:1 中羊占 20/23。",
	"World.wolf_ratio": "狼的相对比例；0 表示不生成狼，修改需要重启。\n例如：20:2:1 中狼占 2/23。",
	"World.sheepdog_ratio": "牧羊犬的相对比例；0 表示不生成狗，修改需要重启。\n例如：20:2:1 中狗占 1/23。",
	"World.perception_interval": "同类软分离采样间隔（模拟秒）；共享统计、狼狗压力和 AI 决策仍每步更新。\n例如：0.125 表示约每 0.125 秒更新一次软分离。",
	"World.separation_distance": "同物种动物之间软分离的作用距离，单位为像素；不等同于物理碰撞。\n例如：24 表示同类靠近到 24 像素内时产生分离移动。",
	"World.death_duration": "死亡立即退出模拟；尸体显示结束后隐藏并回收，单位为模拟秒。\n例如：0.3 表示尸体显示 0.3 秒。",
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
		var counts := draft.get_initial_counts()
		message.text = "Apply restarts the simulation. Initial population: %d sheep, %d wolves, %d dogs." % [counts.x, counts.y, counts.z]
	else:
		message.text = "Apply updates current animals. Elapsed timers are preserved; new thresholds apply next step."

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
		message.text = "Preset missing or incompatible. Only behavior preset version %d is supported; other files are preserved." % SimulationConfig.PRESET_VERSION
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
