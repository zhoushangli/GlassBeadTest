extends SceneTree

var tier: int = 1
var duration: float = 30.0
var warmup: float = 3.0
var max_fps: int = 0
var engine: Node
var scene: Node
var ready_time: int = 0
var started: int = 0
var last_frame: int = 0
var last_sample: int = 0
var frames: int = 0
var sim_started: float = 0.0
var initial_counts := Vector3i.ZERO
var step_times: Array[float] = []
var frame_times: Array[float] = []
var perception_total: float = 0.0
var decision_total: float = 0.0
var movement_total: float = 0.0
var samples: Array[Dictionary] = []
var grass_meals: int = 0
var grass_depletions: int = 0
var grass_regrowths: int = 0
var next_capture: int = 0
var capture_times: Array[float] = [5.0, 60.0, 118.0]
var done: bool = false
var observed_behaviors: Dictionary = {}
var risk_steps: int = 0
var sheep_previous: Dictionary = {}
var sheep_switches: int = 0
var sheep_distance: float = 0.0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tier="):
			tier = maxi(1, argument.trim_prefix("--tier=").to_int())
		elif argument.begins_with("--duration="):
			duration = argument.trim_prefix("--duration=").to_float()
		elif argument.begins_with("--warmup="):
			warmup = argument.trim_prefix("--warmup=").to_float()
		elif argument.begins_with("--max-fps="):
			max_fps = maxi(0, argument.trim_prefix("--max-fps=").to_int())
	call_deferred("_start")


func _start() -> void:
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	var settings: SimulationConfig = scene.simulation_config.copy_config()
	settings.initial_sheep *= tier
	settings.initial_wolves *= tier
	settings.initial_sheepdogs *= tier
	scene.simulation_config = settings
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.simulation_stepped.connect(_record_step)
	engine.grass_changed.connect(_record_grass)
	DisplayServer.window_set_title("GlassBeadTest - Benchmark x%d" % tier)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	ready_time = Time.get_ticks_usec()
	print("BENCHMARK_START tier=%d configured=%s warmup=%.1fs measurement=%.1fs" % [
		tier, engine.entity_service.get_counts(), warmup, duration])


func _process(_delta: float) -> bool:
	if ready_time == 0 or done:
		return false

	var now := Time.get_ticks_usec()
	if started == 0:
		if (now - ready_time) / 1000000.0 >= warmup:
			started = now
			last_frame = now
			last_sample = now
			initial_counts = engine.entity_service.get_counts()
			sim_started = engine.simulation_time
		return false

	if next_capture < capture_times.size() and (now - started) / 1000000.0 >= capture_times[next_capture]:
		var frame := root.get_texture().get_image()
		frame.save_png("res://output/ai-update-20261113-120459/frame-%d.png" % next_capture)
		next_capture += 1
	frames += 1
	frame_times.append((now - last_frame) / 1000.0)
	last_frame = now
	var elapsed := (now - started) / 1000000.0
	if now - last_sample >= 1000000:
		var counts: Vector3i = engine.entity_service.get_counts()
		samples.append({"wall_seconds": elapsed, "simulation_seconds": engine.simulation_time,
			"sheep": counts.x, "wolves": counts.y, "dogs": counts.z,
			"fps_average_so_far": frames / elapsed, "last_step_ms": engine.last_step_ms})
		print("BENCHMARK_SAMPLE tier=%d wall=%.1f fps=%.1f step_ms=%.2f alive=%s sim=%.1f" % [
			tier, elapsed, frames / elapsed, engine.last_step_ms, counts, engine.simulation_time])
		last_sample = now
	if elapsed >= duration:
		_finish(elapsed)
	return false


func _record_step() -> void:
	for animal in engine.entity_service.entities:
		if animal.alive:
			var label: String = animal.KIND_NAMES[animal.kind] + ":" + animal.BEHAVIOR_NAMES[animal.current_behavior]
			observed_behaviors[label] = observed_behaviors.get(label, 0) + 1
			if animal is SheepController:
				if animal.taking_risk:
					risk_steps += 1
				if sheep_previous.has(animal.entity_id):
					var previous: Array = sheep_previous[animal.entity_id]
					sheep_distance += animal.position.distance_to(previous[0])
					if previous[1] != animal.current_behavior:
						sheep_switches += 1
				sheep_previous[animal.entity_id] = [animal.position, animal.current_behavior]
	if started > 0 and not done:
		step_times.append(engine.last_step_ms)
		perception_total += engine.last_perception_ms
		decision_total += engine.last_decision_ms
		movement_total += engine.last_movement_ms


func _record_grass(index: int) -> void:
	if engine.grass_bites[index] == engine.config.grass.bites:
		grass_regrowths += 1
	else:
		grass_meals += 1
		if engine.grass_bites[index] == 0:
			grass_depletions += 1


func _mean(values: Array[float]) -> float:
	var total: float = 0.0
	for value in values:
		total += value
	return total / maxi(1, values.size())


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * fraction)) - 1)]


func _finish(elapsed: float) -> void:
	done = true
	var counts: Vector3i = engine.entity_service.get_counts()
	var result := {
		"observed_behaviors": observed_behaviors, "risk_sheep_steps": risk_steps, "sheep_behavior_switches": sheep_switches, "sheep_distance_total": sheep_distance,
		"tier": tier, "engine": Engine.get_version_info().string,
		"cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": "gl_compatibility", "viewport": "1280x720", "vsync": false,
		"max_fps": Engine.max_fps, "physics_hz": Engine.physics_ticks_per_second,
		"seed": engine.config.random_seed, "warmup_wall_seconds": warmup,
		"measured_wall_seconds": elapsed, "rendered_frames": frames,
		"average_fps": frames / elapsed, "frame_p95_ms": _percentile(frame_times, 0.95),
		"physics_steps": step_times.size(), "step_mean_ms": _mean(step_times),
		"step_p95_ms": _percentile(step_times, 0.95),
		"perception_mean_ms": perception_total / maxi(1, step_times.size()),
		"decision_mean_ms": decision_total / maxi(1, step_times.size()),
		"movement_interaction_mean_ms": movement_total / maxi(1, step_times.size()),
		"simulation_seconds_advanced": engine.simulation_time - sim_started,
		"initial_counts": [initial_counts.x, initial_counts.y, initial_counts.z],
		"final_counts": [counts.x, counts.y, counts.z],
		"captures_total": engine.entity_service.capture_count,
		"grass_meals_total": grass_meals, "grass_depletions_total": grass_depletions,
		"grass_regrowths_total": grass_regrowths,
		"samples": samples
	}
	DirAccess.make_dir_recursive_absolute("res://output/ai-update-20261113-120459/visual")
	var path := "res://output/ai-update-20261113-120459/visual/behavior_cfg_tier_%d.json" % tier
	if max_fps > 0:
		path = "res://output/ai-update-20261113-120459/visual/behavior_cfg_tier_%d_fps_%d.json" % [tier, max_fps]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write benchmark results: " + path)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("BENCHMARK_RESULT ", JSON.stringify(result))
	engine.stop_simulation()
	scene.queue_free()
	call_deferred("quit", 0)
