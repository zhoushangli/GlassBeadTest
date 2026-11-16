class_name DebugPanel
extends PanelContainer

const OPTIONS := {
	"wolf_vision": "Wolf vision", "dog_vision": "Dog vision",
	"tracking": "Target tracking", "memory": "Last seen position",
	"movement": "Movement goals", "protection": "Dog protection / collection",
	"howl": "Howl range and pulse",
}

var service: DebugService

var enabled_toggle: CheckBox
var scope: OptionButton
var controls: Dictionary[String, CheckBox] = {}

func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Debug visuals"
	title.add_theme_font_size_override("font_size", 19)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "Close [Esc]"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	enabled_toggle = CheckBox.new()
	enabled_toggle.text = "Enable overlays [F1]"
	enabled_toggle.toggled.connect(_set_enabled)
	column.add_child(enabled_toggle)
	scope = OptionButton.new()
	scope.add_item("Selected animal only")
	scope.add_item("All animals")
	scope.item_selected.connect(_set_scope)
	column.add_child(scope)
	for key: String in OPTIONS:
		var checkbox := CheckBox.new()
		checkbox.text = OPTIONS[key]
		checkbox.toggled.connect(_set_option.bind(key))
		controls[key] = checkbox
		column.add_child(checkbox)
	var hint := Label.new()
	hint.text = "Visuals only; changes apply immediately.\nSelect an animal by clicking in the arena."
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

func initialize(debug_service: DebugService) -> void:
	service = debug_service
	refresh()

func toggle() -> void:
	if visible:
		close()
	else:
		refresh()
		show()

func close() -> void:
	hide()
	get_viewport().gui_release_focus()

func refresh() -> void:
	if service == null:
		return
	enabled_toggle.set_pressed_no_signal(service.show_details)
	scope.select(0 if service.selected_only else 1)
	for key: String in controls:
		controls[key].set_pressed_no_signal(service.visual_options[key])
		controls[key].disabled = not service.show_details

func _set_enabled(value: bool) -> void:
	service.show_details = value
	refresh()

func _set_scope(index: int) -> void:
	service.selected_only = index == 0
	service.howl_events.clear()
	service.refresh()

func _set_option(value: bool, key: String) -> void:
	service.set_visual_option(key, value)
