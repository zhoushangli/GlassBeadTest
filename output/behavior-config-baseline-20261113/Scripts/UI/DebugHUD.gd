class_name DebugHUD
extends CanvasLayer

@onready var metrics: Label = $Screen/Header/Metrics
@onready var status: Label = $Screen/Header/Status
@onready var selection: Label = $Screen/Footer/Selection
var gameplay_engine: Node


func initialize(engine: Node) -> void:
	gameplay_engine = engine
	refresh()


func refresh() -> void:
	var counts: Vector3i = gameplay_engine.entity_service.get_counts()
	metrics.text = "FPS %d    |    Step %.2f ms    |    Alive %d    |    Sheep %d   Wolves %d   Dogs %d" % [
		Engine.get_frames_per_second(), gameplay_engine.last_step_ms,
		counts.x + counts.y + counts.z, counts.x, counts.y, counts.z]
	status.text = "%s    |    Seed %d    |    Sim %.1f s    |    Captured %d    |    Debug %s" % [
		"PAUSED" if gameplay_engine.paused else "RUNNING", gameplay_engine.config.random_seed,
		gameplay_engine.simulation_time, gameplay_engine.entity_service.capture_count,
		"ON" if gameplay_engine.debug_service.show_details else "OFF"]
	selection.text = gameplay_engine.debug_service.selection_text()
