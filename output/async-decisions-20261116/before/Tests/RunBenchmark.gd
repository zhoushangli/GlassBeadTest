extends SceneTree

var job_totals: Dictionary = {}
var jobs_mode: String = "default"
var jobs_workers: int = 4
var jobs_stages: String = "default"

var main_scene: bool = false
var frame_steps: Array[float] = []
var frame_simulation_ms: Array[float] = []
var pending_frame_steps: int = 0
var pending_frame_simulation_ms: float = 0.0

var entities_count: int = 0
var scenario: String = ""
var tier: int = 1
var tiles: int = 0
var layout: String = "legacy"
var stats_enabled: bool = true
var sampling: String = "stages"
var hud_visible: bool = true
var overlay: String = "on"
var animals_visible: bool = true
var label: String = "benchmark"

var stage_totals: Dictionary = {}
var hotspot_totals: Dictionary = {}
var hotspot_calls: Dictionary = {}

var window_stage_totals: Dictionary = {}
var window_hotspot_totals: Dictionary = {}
var window_hotspot_calls: Dictionary = {}
var window_step_index: int = 0
var window_frame_index: int = 0
var window_elapsed: float = 0.0
var window_debug_ms: Dictionary = {}
var window_debug_calls: Dictionary = {}

var configured_counts := Vector3i.ZERO
var capture_started: int = 0
var preprocessing_totals: Dictionary = {"pressure_samples": 0.0, "pressure_source_pairs": 0.0, "dog_groups": 0.0, "dog_group_hits": 0.0, "dog_candidate_groups": 0.0}

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
var done: bool = false

var fixed_steps: int = 0
var warmup_steps: int = 180

func _initialize() -> void:
	var has_sampling := false
	var has_entities := false
	var has_tier := false
	var has_tiles := false
	var has_layout := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--entry="):
			continue

		var parts := argument.split("=", true, 1)
		if parts.size() != 2:
			_fail("Expected --name=value: " + argument)
			return

		var value := parts[1]
		match parts[0]:
			"--jobs":
				if value not in ["default", "serial", "parallel"]:
					_fail("Expected --jobs=default|serial|parallel")
					return

				jobs_mode = value
			"--job-workers":
				if value not in ["2", "4", "8"]:
					_fail("Expected --job-workers=2|4|8")
					return

				jobs_workers = value.to_int()
			"--job-stages":
				if value not in ["default", "all", "Sheep", "Wolf", "DogAnchor", "Dog", "Grid"]:
					_fail("Invalid job stage")
					return

				jobs_stages = value
			"--main-scene":
				if value not in ["on", "off"]:
					_fail("--main-scene must be on or off")
					return

				main_scene = value == "on"
			"--steps", "--warmup-steps":
				if not value.is_valid_int() or value.to_int() < 0:
					_fail("Expected nonnegative step count: " + argument)
					return
				if parts[0] == "--steps":
					fixed_steps = value.to_int()
				else:
					warmup_steps = value.to_int()
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
			"--sampling":
				if value not in ["off", "stages", "detailed"]:
					_fail("--sampling must be off, stages or detailed")
					return

				has_sampling = true
				sampling = value
			"--hud", "--animals":
				if value not in ["on", "off"]:
					_fail("Expected on or off: " + argument)
					return

				match parts[0]:
					"--hud":
						hud_visible = value == "on"
					"--animals":
						animals_visible = value == "on"
			"--overlay":
				if value not in ["off", "on", "details"]:
					_fail("--overlay must be off, on or details")
					return

				overlay = value
			"--label":
				if value.is_empty() or not value.replace("-", "").replace("_", "").is_valid_identifier():
					_fail("Invalid benchmark label")
					return

				label = value
			"--stats":
				if value not in ["on", "off"]:
					_fail("--stats must be on or off")
					return

				stats_enabled = value == "on"
			_:
				_fail("Unknown argument: " + argument)
				return

	if not has_sampling:
		sampling = "stages" if stats_enabled else "off"
	stats_enabled = sampling != "off"
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
	if main_scene:
		if has_entities or has_tier or has_tiles or has_layout or not scenario.is_empty():
			_fail("--main-scene=on cannot be combined with population/layout options")
			return

		tiles = 0
		tier = 1
		layout = "main_scene"
	call_deferred("_start")

func _fail(message: String) -> void:
	push_error(message)
	done = true
	quit(1)

func _start() -> void:
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	var settings: SimulationConfig = scene.simulation_config.copy_config()
	var base_size := settings.arena_size
	var multiplier := tiles * tiles if tiles > 0 else tier
	if entities_count > 0:
		_prepare_exact_settings(settings)
		settings.initial_total = entities_count
	else:
		settings.initial_total *= multiplier
	if tiles > 0:
		settings.arena_size *= tiles
	var error := settings.validate()
	if not error.is_empty():
		_fail(error)
		scene.free()
		return

	configured_counts = settings.get_initial_counts()

	if tiles > 0 or entities_count > 0:
		settings.initial_total = 0
	scene.simulation_config = settings
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.job_service.max_workers = jobs_workers
	if jobs_mode != "default":
		engine.job_service.parallel_enabled = jobs_mode == "parallel"
	if jobs_stages != "default":
		for stage in engine.job_service.parallel_stages:
			engine.job_service.parallel_stages[stage] = jobs_stages == "all" or stage == jobs_stages

	engine.profile_service.set_performance_stats_enabled(stats_enabled, sampling == "detailed")
	engine.debug_service.hud_enabled = hud_visible
	engine.debug_service.overlay_enabled = overlay != "off"
	engine.debug_service.hud.visible = hud_visible
	engine.debug_service.visible = overlay != "off"
	engine.debug_service.show_details = overlay == "details"
	scene.get_node("World/Animals").visible = animals_visible

	for name in engine.profile_service.STAGE_NAMES:
		stage_totals[name] = 0.0
		window_stage_totals[name] = 0.0
	for name in engine.profile_service.HOTSPOT_NAMES:
		hotspot_totals[name] = 0.0
		hotspot_calls[name] = 0
		window_hotspot_totals[name] = 0.0
		window_hotspot_calls[name] = 0

	for name in engine.profile_service.debug_totals_ms:
		window_debug_ms[name] = 0.0
		window_debug_calls[name] = 0

	if tiles > 0 or entities_count > 0:
		if entities_count > 0:
			_spawn_exact_layout()
		else:
			_spawn_layout(base_size)
		for config in [engine.config, engine.defaults, settings]:
			config.initial_total = configured_counts.x + configured_counts.y + configured_counts.z

	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	engine.simulation_stepped.connect(_record_step)
	DisplayServer.window_set_title("GlassBeadTest - %s %d animals" % [layout, configured_counts.x + configured_counts.y + configured_counts.z])

	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps

	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	run_directory = "res://output/performance/%s_%s_%d_%d" % [stamp, label, OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(run_directory)
	ready_time = Time.get_ticks_usec()
	if fixed_steps > 0:
		print("BENCHMARK_START layout=%s configured=%s warmup_steps=%d measured_steps=%d stats=%s" % [
			layout, configured_counts, warmup_steps, fixed_steps, stats_enabled])
		engine.set_process(false)
		engine.paused = true
		call_deferred("_run_fixed_steps")
	else:
		print("BENCHMARK_START layout=%s tiles=%d configured=%s warmup=%.1fs measurement=%.1fs stats=%s" % [
			layout, tiles, configured_counts, warmup, duration, stats_enabled])

func _run_fixed_steps() -> void:
	var interval: float = 1.0 / engine.simulation_hz
	for index in range(warmup_steps):
		engine.simulate_step(interval)

	initial_counts = engine.entity_service.get_counts()
	capture_started = engine.entity_service.capture_count
	var times: Array[float] = []
	for index in range(fixed_steps):
		var before := Time.get_ticks_usec()
		engine.simulate_step(interval)
		_record_job_timings()
		times.append((Time.get_ticks_usec() - before) / 1000.0)
		for stage in stage_totals:
			stage_totals[stage] += engine.profile_service.last_stages_ms.get(stage, 0.0)

	times.sort()
	var total: float = 0.0
	for value in times:
		total += value
	for stage in stage_totals:
		stage_totals[stage] /= fixed_steps

	var result := {
		"label": label, "mode": "fixed_steps", "job_timings_mean_ms": _job_means(),
		"jobs_parallel_enabled": engine.job_service.parallel_enabled, "job_workers": jobs_workers, "warmup_steps": warmup_steps,
		"measured_steps": fixed_steps, "simulation_hz": engine.simulation_hz,
		"step_mean_ms": total / fixed_steps, "step_p95_ms": times[mini(times.size() - 1, ceili(times.size() * 0.95) - 1)],
		"stages_mean_ms": stage_totals, "configured_counts": [configured_counts.x, configured_counts.y, configured_counts.z],
		"initial_counts": [initial_counts.x, initial_counts.y, initial_counts.z],
		"final_counts": [engine.entity_service.get_counts().x, engine.entity_service.get_counts().y, engine.entity_service.get_counts().z],
		"captures": engine.entity_service.capture_count - capture_started,
		"engine": Engine.get_version_info(), "headless": DisplayServer.get_name() == "headless",
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"arena_size": [engine.config.arena_size.x, engine.config.arena_size.y], "seed": engine.config.random_seed,
		"layout": layout, "scenario": scenario, "sampling": sampling, "max_fps": max_fps,
		"cpu": OS.get_processor_name(), "limboai": _limboai_info(),
	}

	var file := FileAccess.open(run_directory.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("BENCHMARK_RESULT ", run_directory.path_join("result.json"), " ", JSON.stringify(result))
	done = true
	engine.stop_simulation()
	quit()

func _prepare_exact_settings(settings: SimulationConfig) -> void:
	if scenario != "scaled":
		return

	var base_total := settings.initial_total
	if base_total == 0:
		return

	var ratio := float(entities_count) / base_total
	settings.arena_size *= sqrt(ratio)

func _spawn_exact_layout() -> void:
	var positions_rng := RandomNumberGenerator.new()
	positions_rng.seed = engine.config.random_seed
	var lower := Vector2(12.0, 94.0)
	var upper: Vector2 = engine.config.arena_size - Vector2(12.0, 58.0)
	for kind in range(3):
		for index in range(configured_counts[kind]):
			var point := Vector2(positions_rng.randf_range(lower.x, upper.x), positions_rng.randf_range(lower.y, upper.y))
			engine.entity_service.spawn(kind, 1, point)

func _spawn_layout(base_size: Vector2) -> void:
	var positions_rng := RandomNumberGenerator.new()
	positions_rng.seed = engine.config.random_seed
	var regions := tiles * tiles
	for region in range(regions):
		var offset := Vector2(region % tiles, floori(float(region) / tiles)) * base_size
		if layout == "cluster":
			offset = (engine.config.arena_size - base_size) * 0.5
		for kind in range(3):
			var count := configured_counts[kind] / regions + (1 if region < configured_counts[kind] % regions else 0)
			for index in range(count):
				var point := base_size * 0.5
				match kind:
					AnimalEntity.Kind.SHEEP:
						point += Vector2(positions_rng.randf_range(-440.0, 440.0), positions_rng.randf_range(-220.0, 220.0))
					AnimalEntity.Kind.WOLF:
						point = Vector2(40.0 if index % 2 == 0 else base_size.x - 40.0, positions_rng.randf_range(100.0, base_size.y - 65.0))
					AnimalEntity.Kind.SHEEPDOG:
						point += Vector2.from_angle(TAU * float(index) / maxi(1, count)) * 100.0
				engine.entity_service.spawn(kind, 1, point + offset)

func _process(_delta: float) -> bool:
	if fixed_steps > 0:
		return false
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
			engine.profile_service.reset()
		return false

	frame_steps.append(float(pending_frame_steps))
	frame_simulation_ms.append(pending_frame_simulation_ms)
	pending_frame_steps = 0
	pending_frame_simulation_ms = 0.0
	frames += 1
	frame_times.append((now - last_frame) / 1000.0)
	last_frame = now

	var elapsed := (now - started) / 1000000.0
	if now - last_sample >= 1000000:
		var counts: Vector3i = engine.entity_service.get_counts()
		_record_sample(elapsed)
		print("BENCHMARK_SAMPLE tier=%d wall=%.1f loop_hz=%.1f step_ms=%.2f alive=%s sim=%.1f" % [
			tier, elapsed, frames / elapsed, engine.profile_service.last_step_ms, counts, engine.simulation_time])
		last_sample = now
	if elapsed >= duration:
		_finish(elapsed)
	return false

func _record_step() -> void:
	if started > 0 and not done:
		pending_frame_steps += 1
		pending_frame_simulation_ms += engine.profile_service.last_step_ms
		step_times.append(engine.profile_service.last_step_ms)
		_record_job_timings()
		perception_total += engine.profile_service.last_perception_ms
		decision_total += engine.profile_service.last_decision_ms
		movement_total += engine.profile_service.last_movement_ms

		for name in stage_totals:
			stage_totals[name] += engine.profile_service.last_stages_ms[name]
		for name in hotspot_totals:
			hotspot_totals[name] += engine.profile_service.last_hotspots_ms[name]
			hotspot_calls[name] += engine.profile_service.last_hotspot_calls[name]

		var service: GridService = engine.grid_service
		preprocessing_totals.pressure_samples += service.pressure_sample_count
		preprocessing_totals.pressure_source_pairs += service.pressure_source_pairs
		preprocessing_totals.dog_groups += engine.dog_system.shared_group_count
		preprocessing_totals.dog_group_hits += engine.dog_system.shared_group_hits
		preprocessing_totals.dog_candidate_groups += engine.dog_system.shared_candidate_groups
		spatial_queries += service.spatial_query_count
		spatial_candidates += service.spatial_candidate_count
		spatial_max_candidates = maxi(spatial_max_candidates, service.spatial_max_candidates)
		spatial_max_occupancy = maxi(spatial_max_occupancy, service.spatial_max_occupancy)
		spatial_cells_total += service.spatial_nonempty_cells

func _record_job_timings() -> void:
	for stage in engine.job_service.last_timings:
		if not job_totals.has(stage):
			job_totals[stage] = {"prepare_ms": 0.0, "dispatch_ms": 0.0, "wait_ms": 0.0, "execute_ms": 0.0, "submit_ms": 0.0, "total_ms": 0.0, "batches": 0.0, "steps": 0}
		var totals: Dictionary = job_totals[stage]
		var timing: Dictionary = engine.job_service.last_timings[stage]
		for metric in totals:
			if metric != "steps":
				totals[metric] += timing[metric]
		totals.steps += 1

func _job_means() -> Dictionary:
	var result := job_totals.duplicate(true)
	for stage in result:
		for metric in result[stage]:
			if metric != "steps":
				result[stage][metric] /= maxi(1, result[stage].steps)
	return result

func _record_sample(elapsed: float) -> void:
	var counts: Vector3i = engine.entity_service.get_counts()
	var steps := step_times.size() - window_step_index
	var sample := {"wall_seconds": elapsed, "window_wall_seconds": elapsed - window_elapsed,
		"simulation_seconds": engine.simulation_time, "simulation_steps": steps, "physics_steps": steps,
		"sheep": counts.x, "wolves": counts.y, "dogs": counts.z,
		"loop_hz_average_so_far": frames / elapsed, "last_step_ms": engine.profile_service.last_step_ms,
		"window_loop_hz": (frames - window_frame_index) / maxf(0.000001, elapsed - window_elapsed),
		"step_mean_ms": _mean(step_times.slice(window_step_index)),
		"step_p95_ms": _percentile(step_times.slice(window_step_index), 0.95),
		"frame_p95_ms": _percentile(frame_times.slice(window_frame_index), 0.95),
		"stages_mean_ms": {}, "hotspots": {}, "debug": {},
		"preprocessing_last_step": {"pressure_samples": engine.grid_service.pressure_sample_count, "pressure_source_pairs": engine.grid_service.pressure_source_pairs,
			"dog_groups": engine.dog_system.shared_group_count, "dog_group_hits": engine.dog_system.shared_group_hits},
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"rendered_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_process_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0}

	for name in stage_totals:
		sample.stages_mean_ms[name] = (stage_totals[name] - window_stage_totals[name]) / maxi(1, steps)
		window_stage_totals[name] = stage_totals[name]

	for name in hotspot_totals:
		var total: float = hotspot_totals[name] - window_hotspot_totals[name]
		var calls: int = hotspot_calls[name] - window_hotspot_calls[name]
		sample.hotspots[name] = {"total_ms": total, "calls": calls, "mean_per_step_ms": total / maxi(1, steps), "mean_per_call_ms": total / maxi(1, calls)}
		window_hotspot_totals[name] = hotspot_totals[name]
		window_hotspot_calls[name] = hotspot_calls[name]

	for name in engine.profile_service.debug_totals_ms:
		var total: float = engine.profile_service.debug_totals_ms[name] - window_debug_ms[name]
		var calls: int = engine.profile_service.debug_calls[name] - window_debug_calls[name]
		sample.debug[name] = {"total_ms": total, "calls": calls, "mean_per_call_ms": total / maxi(1, calls)}
		window_debug_ms[name] = engine.profile_service.debug_totals_ms[name]
		window_debug_calls[name] = engine.profile_service.debug_calls[name]

	samples.append(sample)
	window_step_index = step_times.size()
	window_frame_index = frames
	window_elapsed = elapsed

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
	if elapsed > window_elapsed:
		_record_sample(elapsed)
	var stages_mean: Dictionary = {}
	var hotspots: Dictionary = {}
	var debug: Dictionary = {}

	for name in stage_totals:
		stages_mean[name] = stage_totals[name] / maxi(1, step_times.size())

	for name in hotspot_totals:
		hotspots[name] = {"total_ms": hotspot_totals[name], "calls": hotspot_calls[name],
			"mean_per_step_ms": hotspot_totals[name] / maxi(1, step_times.size()),
			"mean_per_call_ms": hotspot_totals[name] / maxi(1, hotspot_calls[name])}

	for name in engine.profile_service.debug_totals_ms:
		debug[name] = {"total_ms": engine.profile_service.debug_totals_ms[name], "calls": engine.profile_service.debug_calls[name],
			"mean_per_call_ms": engine.profile_service.debug_totals_ms[name] / maxi(1, engine.profile_service.debug_calls[name])}

	var preprocessing_mean: Dictionary = {}
	for name in preprocessing_totals:
		preprocessing_mean[name] = preprocessing_totals[name] / maxi(1, step_times.size())

	var result := {
		"job_timings_mean_ms": _job_means(), "jobs_parallel_enabled": engine.job_service.parallel_enabled,
		"result_version": 4, "jobs_mode": jobs_mode, "job_workers": jobs_workers, "job_stages": engine.job_service.parallel_stages, "label": label, "sampling": sampling,
		"visibility": {"hud": hud_visible, "overlay": overlay, "animals": animals_visible},
		"stages_mean_ms": stages_mean, "hotspots": hotspots, "debug": debug,
		"preprocessing_mean_per_step": preprocessing_mean,
		"steering_mean_ms": stages_mean["Steering"],
		"decision_steering_mean_ms": stages_mean["Decision"] + stages_mean["Steering"],
		"movement_mean_ms": stages_mean["Movement"], "interaction_mean_ms": stages_mean["Interaction"],
		"cleanup_mean_ms": stages_mean["Cleanup"],
		"gpu_timing_available": false,
		"entities": entities_count, "scenario": scenario, "layout_version": 1,
		"tier": tier, "tiles": tiles, "layout": layout, "engine": Engine.get_version_info(),
		"limboai": _limboai_info(), "stats_enabled": stats_enabled,
		"script_profiler_active": EngineDebugger.is_profiling("scripts"),
		"headless": DisplayServer.get_name() == "headless",
		"arena_size": [engine.config.arena_size.x, engine.config.arena_size.y],
		"configured_counts": [configured_counts.x, configured_counts.y, configured_counts.z],
		"cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"display_driver": DisplayServer.get_name(), "viewport": [root.size.x, root.size.y],
		"camera_zoom": scene.get_node("Camera2D").zoom.x, "vsync": false,
		"max_fps": Engine.max_fps, "physics_hz": Engine.physics_ticks_per_second,
		"simulation_hz": engine.simulation_hz, "max_steps_per_frame": engine.max_steps_per_frame,
		"seed": engine.config.random_seed, "warmup_wall_seconds": warmup,
		"measured_wall_seconds": elapsed, "process_iterations": frames,
		"loop_hz": frames / elapsed, "loop_mean_ms": _mean(frame_times),
		"loop_p95_ms": _percentile(frame_times, 0.95), "loop_max_ms": frame_times.max() if not frame_times.is_empty() else 0.0,
		"simulation_steps": step_times.size(), "physics_steps": step_times.size(), "step_mean_ms": _mean(step_times),
		"steps_per_frame_mean": _mean(frame_steps), "steps_per_frame_p95": _percentile(frame_steps, 0.95),
		"simulation_per_frame_mean_ms": _mean(frame_simulation_ms),
		"simulation_per_frame_p95_ms": _percentile(frame_simulation_ms, 0.95),
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
		"retained_entities": engine.entity_service.data.row_to_slot.size(),
		"pooled_entities": engine.entity_service.data.row_to_slot.size() - engine.entity_service.data.retained_count,
		"corpse_entities": engine.entity_service.data.retained_count - engine.entity_service.data.active_count,
		"captures_during_measurement": engine.entity_service.capture_count - capture_started,
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
