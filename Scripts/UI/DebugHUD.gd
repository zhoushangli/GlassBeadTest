class_name DebugHUD
extends CanvasLayer

@onready var metrics: Label = $Screen/Header/Metrics
@onready var status: Label = $Screen/Header/Status
@onready var selection: Label = $Screen/Footer/Selection
@onready var parameters: RuntimeConfigPanel = $Screen/Parameters
@onready var debug_panel: DebugPanel = $Screen/DebugPanel

var gameplay_engine: Node

func initialize(engine: Node) -> void:
	gameplay_engine = engine
	parameters.initialize(engine)
	debug_panel.initialize(engine.debug_service)
	if not $Screen/Header/ParametersButton.pressed.is_connected(_toggle_parameters):
		$Screen/Header/ParametersButton.pressed.connect(_toggle_parameters)
		$Screen/Header/DebugButton.pressed.connect(_toggle_debug)
	refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F2:
				_toggle_parameters()
				get_viewport().set_input_as_handled()
			KEY_F3:
				_toggle_debug()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if debug_panel.visible:
					debug_panel.close()
					get_viewport().set_input_as_handled()
				elif parameters.visible:
					parameters.close()
					get_viewport().set_input_as_handled()

func _toggle_parameters() -> void:
	debug_panel.close()
	parameters.toggle()

func _toggle_debug() -> void:
	parameters.close()
	debug_panel.toggle()

func refresh() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var counts: Vector3i = gameplay_engine.entity_service.get_counts()
	var frequency := "Paused" if gameplay_engine.paused else "%.1f / %.0f Hz" % [gameplay_engine.actual_simulation_hz, gameplay_engine.config.simulation_hz]
	metrics.text = "FPS %d | Sim %s | Step %.2f ms | Alive %d | Sheep %d Wolves %d Dogs %d" % [
		Engine.get_frames_per_second(), frequency, gameplay_engine.profile_service.last_step_ms,
		counts.x + counts.y + counts.z, counts.x, counts.y, counts.z]

	var logic: AnimalService = gameplay_engine.animal_service
	var requests := logic.actual_request_hz if not gameplay_engine.paused else Vector3.ZERO
	var applications := logic.actual_apply_hz if not gameplay_engine.paused else Vector3.ZERO
	var hunters: int = 0
	for wolf_row in gameplay_engine.entity_service.wolf_rows:
		var wolf := data.handles[wolf_row]
		if data.identity_alive[wolf.row] and data.wolf_hunting[wolf.row]:
			hunters += 1

	status.text = "%s | Seed %d | Sim %.1f s | Captured %d | %s | Debug %s" % [
		"PAUSED" if gameplay_engine.paused else "RUNNING", gameplay_engine.config.random_seed,
		gameplay_engine.simulation_time, gameplay_engine.entity_service.capture_count,
		"Hunting %d" % hunters,
		"ON" if gameplay_engine.debug_service.show_details else "OFF"]
	status.text += " | Logic S/W/D target %d/%d/%d req %.0f/%.0f/%.0f apply %.0f/%.0f/%.0f Hz" % [
		gameplay_engine.config.sheep_update_hz, gameplay_engine.config.wolf_update_hz, gameplay_engine.config.sheepdog_update_hz,
		requests.x, requests.y, requests.z, applications.x, applications.y, applications.z]
	selection.text = gameplay_engine.debug_service.selection_text()
	parameters.refresh()
	if debug_panel.visible:
		debug_panel.refresh()
