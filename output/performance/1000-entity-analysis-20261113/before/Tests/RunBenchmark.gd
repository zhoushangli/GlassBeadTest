extends SceneTree

var entities_count: int = 0
var scenario: String = ""
var tier: int = 1
var tiles: int = 0
var layout: String = "legacy"
var stats_enabled: bool = true
var configured_counts := Vector3i.ZERO
var capture_started: int = 0
var spatial_queries: int = 0
var spatial_candidates: int = 0
var spatial_max_candidates: int = 0
var spatial_max_occupancy: int = 0
var spatial_cells_total: int = 0
var run_directory: String
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
var done: bool = false

func _initialize() -> void:
	var has_entities := false
	var has_tier := false
	var has_tiles := false
	var has_layout := false
	for argument in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		if parts.size() != 2:
			_fail("Expected --name=value: " + argument)
			return
		var value := parts[1]
		match parts[0]:
			"--entities", "--tier", "--tiles", "--max-fps":
				if not value.is_valid_int():
					_fail("Expected integer: " + argument)
					return
				match parts[0]:
					"--entities":
						has_entities = true
						entities_count = value.to_int()
					"--tier":
						has_tier = true
						tier = value.to_int()
					"--tiles":
						has_tiles = true
						tiles = value.to_int()
					"--max-fps":
						max_fps = value.to_int()
			"--duration", "--warmup":
				if not value.is_valid_float():
					_fail("Expected seconds: " + argument)
					return
				if parts[0] == "--duration":
					duration = value.to_float()
				else:
					warmup = value.to_float()
			"--scenario":
				scenario = value
			"--layout":
				has_layout = true
				layout = value
			"--stats":
				if value not in ["on", "off"]:
					_fail("--stats must be on or off")
					return
				stats_enabled = value == "on"
			_:
				_fail("Unknown argument: " + argument)
				return
	if tier < 1 or max_fps < 0 or not is_finite(duration) or duration <= 0.0 or not is_finite(warmup) or warmup < 0.0:
		_fail("Invalid tier, frame cap, or duration")
		return
	if has_entities or not scenario.is_empty():
		if entities_count not in [1000, 2000, 3000, 4000] or scenario not in ["scaled", "fixed"] or has_tier or has_tiles or has_layout:
			_fail("Use --entities=1000|2000|3000|4000 --scenario=scaled|fixed without tier, tiles or layout")
			return
		layout = "uniform_v1"
	if entities_count == 0 and ((has_tier and has_tiles) or (has_tiles and tiles not in [1, 2, 4, 6]) or (tiles == 0 and layout != "legacy") or (tiles != 0 and layout not in ["spread", "cluster"])):
		_fail("Use --tier=N alone, or --tiles=1|2|4|6 with --layout=spread|cluster")
		return
	call_deferred("_start")

func _fail(message: String) -> void:
	push_error(message)
	done = true
	quit(1)

func _start() -> void:
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	var settings: SimulationConfig = scene.simulation_config.copy_config()
	var base_counts := Vector3i(settings.initial_sheep, settings.initial_wolves, settings.initial_sheepdogs)
	var base_size := settings.arena_size
	var multiplier := tiles * tiles if tiles > 0 else tier
	configured_counts = base_counts * multiplier
	if entities_count > 0:
		configured_counts = _exact_counts(entities_count, base_counts)
		_prepare_exact_settings(settings)
	settings.initial_sheep = configured_counts.x
	settings.initial_wolves = configured_counts.y
	settings.initial_sheepdogs = configured_counts.z
	if tiles > 0:
		settings.arena_size *= tiles
		var base_patches := settings.grass.positions.duplicate()
		settings.grass.positions.clear()
		for y in range(tiles):
			for x in range(tiles):
				for point in base_patches:
					settings.grass.positions.append(point + Vector2(x, y) * base_size)
	var error := settings.validate()
	if not error.is_empty():
		_fail(error)
		scene.free()
		return
	if tiles > 0 or entities_count > 0:
		settings.initial_sheep = 0
		settings.initial_wolves = 0
		settings.initial_sheepdogs = 0
	scene.simulation_config = settings
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_performance_stats_enabled(stats_enabled)
	if tiles > 0 or entities_count > 0:
		if entities_count > 0:
			_spawn_exact_layout()
		else:
			_spawn_layout(base_counts, base_size)
		for config in [engine.config, engine.defaults, settings]:
			config.initial_sheep = configured_counts.x
			config.initial_wolves = configured_counts.y
			config.initial_sheepdogs = configured_counts.z
	var camera: Camera2D = scene.get_node("Camera2D")
	camera.zoom = Vector2.ONE * minf(1280.0 / settings.arena_size.x, 720.0 / settings.arena_size.y)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	engine.simulation_stepped.connect(_record_step)
	engine.grass_changed.connect(_record_grass)
	DisplayServer.window_set_title("GlassBeadTest - %s %d animals" % [layout, configured_counts.x + configured_counts.y + configured_counts.z])
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	run_directory = "res://output/performance/%s_%d_%d_%s_%d" % [stamp, OS.get_process_id(), Time.get_ticks_usec(), layout, multiplier]
	DirAccess.make_dir_recursive_absolute(run_directory)
	ready_time = Time.get_ticks_usec()
	print("BENCHMARK_START layout=%s tiles=%d configured=%s warmup=%.1fs measurement=%.1fs stats=%s" % [
		layout, tiles, configured_counts, warmup, duration, stats_enabled])

func _exact_counts(total: int, weights: Vector3i) -> Vector3i:
	var weight_sum := weights.x + weights.y + weights.z
	var counts := Vector3i.ZERO
	var remainders: Array[float] = []
	for kind in range(3):
		var share := float(total) * weights[kind] / weight_sum
		counts[kind] = floori(share)
		remainders.append(share - counts[kind])
	for index in range(total - counts.x - counts.y - counts.z):
		var kind := remainders.find(remainders.max())
		counts[kind] += 1
		remainders[kind] = -1.0
	return counts

func _prepare_exact_settings(settings: SimulationConfig) -> void:
	if scenario != "scaled":
		return
	var base_total := settings.initial_sheep + settings.initial_wolves + settings.initial_sheepdogs
	var ratio := float(entities_count) / base_total
	settings.arena_size *= sqrt(ratio)
	var patch_count := roundi(settings.grass.positions.size() * ratio)
	var columns := ceili(sqrt(patch_count * settings.arena_size.x / settings.arena_size.y))
	var rows := ceili(float(patch_count) / columns)
	var margin := Vector2.ONE * (settings.grass.patch_radius + 12.0)
	var area := settings.arena_size - margin * 2.0
	settings.grass.positions.clear()
	for index in range(patch_count):
		var x := (float(index % columns) + 0.5) / columns
		var y := (floorf(float(index) / columns) + 0.5) / rows
		settings.grass.positions.append(margin + Vector2(x, y) * area)

func _spawn_exact_layout() -> void:
	var positions_rng := RandomNumberGenerator.new()
	positions_rng.seed = engine.config.random_seed
	var lower := Vector2(12.0, 94.0)
	var upper: Vector2 = engine.config.arena_size - Vector2(12.0, 58.0)
	for kind in range(3):
		for index in range(configured_counts[kind]):
			var point := Vector2(positions_rng.randf_range(lower.x, upper.x), positions_rng.randf_range(lower.y, upper.y))
			engine.entity_service.spawn(kind, 1, point)

func _spawn_layout(base_counts: Vector3i, base_size: Vector2) -> void:
	var positions_rng := RandomNumberGenerator.new()
	positions_rng.seed = engine.config.random_seed
	for region in range(tiles * tiles):
		var offset := Vector2(region % tiles, floori(float(region) / tiles)) * base_size
		if layout == "cluster":
			offset = (engine.config.arena_size - base_size) * 0.5
		for kind in range(3):
			for index in range(base_counts[kind]):
				var point := base_size * 0.5
				match kind:
					AnimalController.Kind.SHEEP:
						point += Vector2(positions_rng.randf_range(-440.0, 440.0), positions_rng.randf_range(-220.0, 220.0))
					AnimalController.Kind.WOLF:
						point = Vector2(40.0 if index % 2 == 0 else base_size.x - 40.0, positions_rng.randf_range(100.0, base_size.y - 65.0))
					AnimalController.Kind.SHEEPDOG:
						point += Vector2.from_angle(TAU * float(index) / maxi(1, base_counts.z)) * 100.0
				engine.entity_service.spawn(kind, 1, point + offset)

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
			capture_started = engine.entity_service.capture_count
			grass_meals = 0
			grass_depletions = 0
			grass_regrowths = 0
			engine.reset_performance_stats()
		return false

	frames += 1
	frame_times.append((now - last_frame) / 1000.0)
	last_frame = now
	var elapsed := (now - started) / 1000000.0
	if now - last_sample >= 1000000:
		var counts: Vector3i = engine.entity_service.get_counts()
		samples.append({"wall_seconds": elapsed, "simulation_seconds": engine.simulation_time,
			"sheep": counts.x, "wolves": counts.y, "dogs": counts.z,
			"loop_hz_average_so_far": frames / elapsed, "last_step_ms": engine.last_step_ms})
		print("BENCHMARK_SAMPLE tier=%d wall=%.1f loop_hz=%.1f step_ms=%.2f alive=%s sim=%.1f" % [
			tier, elapsed, frames / elapsed, engine.last_step_ms, counts, engine.simulation_time])
		last_sample = now
	if elapsed >= duration:
		_finish(elapsed)
	return false

func _record_step() -> void:
	if started > 0 and not done:
		step_times.append(engine.last_step_ms)
		perception_total += engine.last_perception_ms
		decision_total += engine.last_decision_ms
		movement_total += engine.last_movement_ms
		var service: EntityService = engine.entity_service
		spatial_queries += service.spatial_query_count
		spatial_candidates += service.spatial_candidate_count
		spatial_max_candidates = maxi(spatial_max_candidates, service.spatial_max_candidates)
		spatial_max_occupancy = maxi(spatial_max_occupancy, service.spatial_max_occupancy)
		spatial_cells_total += service.spatial_nonempty_cells

func _record_grass(index: int) -> void:
	if started == 0 or done:
		return
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
		"entities": entities_count, "scenario": scenario, "layout_version": 1,
		"tier": tier, "tiles": tiles, "layout": layout, "engine": Engine.get_version_info(),
		"limboai": _limboai_info(), "stats_enabled": stats_enabled,
		"script_profiler_active": EngineDebugger.is_profiling("scripts"),
		"headless": DisplayServer.get_name() == "headless",
		"arena_size": [engine.config.arena_size.x, engine.config.arena_size.y],
		"grass_patches": engine.config.grass.positions.size(), "grass_points": engine.grass_positions.size(),
		"configured_counts": [configured_counts.x, configured_counts.y, configured_counts.z],
		"cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"display_driver": DisplayServer.get_name(), "viewport": [root.size.x, root.size.y],
		"camera_zoom": scene.get_node("Camera2D").zoom.x, "vsync": false,
		"max_fps": Engine.max_fps, "physics_hz": Engine.physics_ticks_per_second,
		"seed": engine.config.random_seed, "warmup_wall_seconds": warmup,
		"measured_wall_seconds": elapsed, "process_iterations": frames,
		"loop_hz": frames / elapsed, "loop_mean_ms": _mean(frame_times),
		"loop_p95_ms": _percentile(frame_times, 0.95), "loop_max_ms": frame_times.max() if not frame_times.is_empty() else 0.0,
		"physics_steps": step_times.size(), "step_mean_ms": _mean(step_times),
		"step_p95_ms": _percentile(step_times, 0.95),
		"step_max_ms": step_times.max() if not step_times.is_empty() else 0.0,
		"spatial_queries": spatial_queries, "spatial_candidates": spatial_candidates,
		"spatial_queries_per_step": float(spatial_queries) / maxi(1, step_times.size()),
		"spatial_candidates_per_query": float(spatial_candidates) / maxi(1, spatial_queries),
		"spatial_max_candidates": spatial_max_candidates, "spatial_max_occupancy": spatial_max_occupancy,
		"spatial_nonempty_cells_mean": float(spatial_cells_total) / maxi(1, step_times.size()),
		"perception_mean_ms": perception_total / maxi(1, step_times.size()),
		"decision_mean_ms": decision_total / maxi(1, step_times.size()),
		"movement_interaction_mean_ms": movement_total / maxi(1, step_times.size()),
		"simulation_seconds_at_measurement_start": sim_started,
		"simulation_seconds_advanced": engine.simulation_time - sim_started,
		"initial_counts": [initial_counts.x, initial_counts.y, initial_counts.z],
		"final_counts": [counts.x, counts.y, counts.z],
		"captures_during_measurement": engine.entity_service.capture_count - capture_started,
		"grass_meals_total": grass_meals, "grass_depletions_total": grass_depletions,
		"grass_regrowths_total": grass_regrowths,
		"samples": samples
	}
	if DisplayServer.get_name() != "headless":
		result["average_fps"] = frames / elapsed
		result["frame_p95_ms"] = _percentile(frame_times, 0.95)
	result["simulation_wall_ratio"] = (engine.simulation_time - sim_started) / elapsed
	var path := run_directory + "/result.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write benchmark results: " + path)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("BENCHMARK_RESULT ", path, " ", JSON.stringify(result))
	engine.stop_simulation()
	scene.queue_free()
	call_deferred("quit", 0)

func _limboai_info() -> Dictionary:
	var info := {"version": "unknown", "binary_sha256": "", "binary": "res://addons/limboai/bin/liblimboai.windows.editor.x86_64.dll"}
	if FileAccess.file_exists("res://addons/limboai/version.txt"):
		info.version = FileAccess.get_file_as_string("res://addons/limboai/version.txt").strip_edges()
	var limbo := Engine.get_singleton("LimboUtility") if Engine.has_singleton("LimboUtility") else null
	if limbo != null and limbo.has_method("get_version_info"):
		info["version"] = limbo.call("get_version_info")
	if FileAccess.file_exists(info.binary):
		info.binary_sha256 = FileAccess.get_sha256(info.binary)
	return info
