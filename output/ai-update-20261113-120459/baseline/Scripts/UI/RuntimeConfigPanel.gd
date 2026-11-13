class_name RuntimeConfigPanel
extends PanelContainer

const FIELD_HELP := {
	"initial_sheep": "Initial population. Applying a change restarts the simulation.",
	"initial_wolves": "Initial population. Applying a change restarts the simulation.",
	"initial_sheepdogs": "Initial population. Applying a change restarts the simulation.",
	"random_seed": "Random seed. Applying a change restarts the simulation.",
	"initial_hunger_min": "Minimum starting hunger for newly spawned sheep. Existing hunger is preserved.",
	"initial_hunger_max": "Maximum starting hunger for newly spawned sheep. Existing hunger is preserved.",
	"hungry_threshold": "Start seeking food at this hunger. Must exceed full threshold.",
	"full_threshold": "Stop feeding at this hunger. Must be below hungry threshold.",
	"hunger_per_bite": "Hunger removed after one completed bite.",
	"rest_duration_min": "Minimum rest before a new hunt. Existing sampled rest keeps its duration.",
	"rest_duration_max": "Maximum rest before a new hunt. Existing sampled rest keeps its duration.",
	"regrow_duration": "Seconds before grass regrows. Applies to newly depleted grass.",
	"max_hunters": "Maximum simultaneous hunters. Lowering it also releases excess current hunters.",
	"patch_radius": "Grass patch radius. Applying a change restarts the simulation.",
	"per_patch": "Grass points per patch. Applying a change restarts the simulation.",
	"bites": "Food per grass point. Applying a change restarts the simulation."
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
	label.tooltip_text = FIELD_HELP.get(property.name, label.text)
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
		message.text = "No valid saved CFG_Runtime.tres preset was found."
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
