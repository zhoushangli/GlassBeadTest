extends SceneTree

var engine: Node
var scene: Node
var no_wolves: bool = false
var measured_until: float = 120.0
var last_sample: int = -1
var meals: int = 0
var switches: int = 0
var last_patch: Dictionary = {}
var last_meals: Dictionary = {}
var hunt_seconds: float = 0.0
var done: bool = false
var records: Array[Dictionary] = []


func _initialize() -> void:
	no_wolves = OS.get_cmdline_user_args().has("--no-wolves")
	call_deferred("_start")


func _start() -> void:
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	var settings: SimulationConfig = scene.simulation_config.copy_config()
	if no_wolves:
		settings.initial_wolves = 0
	scene.simulation_config = settings
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.simulation_stepped.connect(_observe)
	DisplayServer.window_set_title("GlassBeadTest - Behavior observation")
	Engine.max_fps = 60


func _observe() -> void:
	if done:
		return
	if engine.hunt_active:
		hunt_seconds += 1.0 / 60.0
	for sheep in engine.entity_service.sheep:
		if sheep.meals_eaten > last_meals.get(sheep.entity_id, 0):
			meals += sheep.meals_eaten - last_meals.get(sheep.entity_id, 0)
			if last_patch.has(sheep.entity_id) and last_patch[sheep.entity_id] != sheep.last_meal_patch:
				switches += 1
			last_meals[sheep.entity_id] = sheep.meals_eaten
			last_patch[sheep.entity_id] = sheep.last_meal_patch
	var sample: int = int(engine.simulation_time / 10.0)
	if sample > last_sample:
		last_sample = sample
		var center := Vector2.ZERO
		var living: int = 0
		var behaviors: Dictionary = {}
		for sheep in engine.entity_service.sheep:
			if not sheep.alive:
				continue
			living += 1
			center += sheep.position
			behaviors[sheep.current_behavior] = behaviors.get(sheep.current_behavior, 0) + 1
		center /= maxi(1, living)
		var spread: float = 0.0
		for sheep in engine.entity_service.sheep:
			if sheep.alive:
				spread += sheep.position.distance_to(center)
		var result := {"seconds": engine.simulation_time, "sheep": living, "meals": meals,
			"patch_switches_after_meal": switches, "hunts": engine.hunt_rounds,
			"hunt_seconds": hunt_seconds, "captures": engine.entity_service.capture_count,
			"mean_distance_to_center": spread / maxi(1, living), "behaviors": behaviors,
			"fps": Engine.get_frames_per_second(), "step_ms": engine.last_step_ms}
		records.append(result)
		print("OBSERVATION ", JSON.stringify(result))
	if engine.simulation_time >= measured_until:
		done = true
		var name := "no_wolves" if no_wolves else "default"
		var file := FileAccess.open("res://output/behavior_observation_" + name + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify(records, "\t"))
		file.close()
		engine.paused = true
		print("OBSERVATION_COMPLETE ", name)
		call_deferred("_finish")


func _finish() -> void:
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	quit()
