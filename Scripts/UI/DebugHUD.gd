class_name DebugHUD
extends CanvasLayer

@onready var metrics: Label = $Screen/Header/Metrics
@onready var status: Label = $Screen/Header/Status
@onready var selection: Label = $Screen/Footer/Selection
@onready var parameters: RuntimeConfigPanel = $Screen/Parameters
var gameplay_engine: Node

func initialize(engine: Node) -> void:
	gameplay_engine = engine
	parameters.initialize(engine)
	if not $Screen/Header/ParametersButton.pressed.is_connected(parameters.toggle):
		$Screen/Header/ParametersButton.pressed.connect(parameters.toggle)
	refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F2:
				parameters.toggle()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if parameters.visible:
					parameters.close()
					get_viewport().set_input_as_handled()

func refresh() -> void:
	var counts: Vector3i = gameplay_engine.entity_service.get_counts()
	metrics.text = "FPS %d    |    Step %.2f ms    |    Alive %d    |    Sheep %d   Wolves %d   Dogs %d" % [
		Engine.get_frames_per_second(), gameplay_engine.last_step_ms,
		counts.x + counts.y + counts.z, counts.x, counts.y, counts.z]
	var hunters: int = 0
	for wolf in gameplay_engine.entity_service.wolves:
		if wolf.alive and wolf.hunting:
			hunters += 1
	status.text = "%s    |    Seed %d    |    Sim %.1f s    |    Captured %d    |    %s    |    Debug %s" % [
		"PAUSED" if gameplay_engine.paused else "RUNNING", gameplay_engine.config.random_seed,
		gameplay_engine.simulation_time, gameplay_engine.entity_service.capture_count,
		"Hunting %d" % hunters,
		"ON" if gameplay_engine.debug_service.show_details else "OFF"]
	selection.text = gameplay_engine.debug_service.selection_text()
	parameters.refresh()
