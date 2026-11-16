extends "res://Tests/RunBenchmark.gd"

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_verify")

func _process(_delta: float) -> bool:
	return false

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _state() -> Array:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var values: Array = [engine.rng.state, engine.entity_service.capture_count]
	for animal in engine.entity_service.entities:
		var target_id: int = data.identity_entity_id[data.live(data.memory_target[animal.row]).row] if g_gameplayEngine.animal_system.is_live(animal, data.live(data.memory_target[animal.row])) else 0
		values.append([data.identity_entity_id[animal.row], data.motion_position[animal.row], data.motion_velocity[animal.row], data.brain_current_behavior[animal.row], target_id, data.identity_alive[animal.row], data.motion_facing[animal.row], data.memory_last_seen_position[animal.row], data.memory_last_seen_velocity[animal.row], data.memory_unseen_elapsed[animal.row]])
		if data.identity_kind[animal.row] == AnimalEntity.Kind.SHEEP:
			values.append([data.sheep_threat_strength[animal.row], data.sheep_panic_strength[animal.row]])
		elif data.identity_kind[animal.row] == AnimalEntity.Kind.WOLF:
			values.append([data.wolf_hunting[animal.row], data.wolf_hunt_elapsed[animal.row], data.wolf_charging[animal.row], data.wolf_strategy[animal.row], data.wolf_strategy_failures[animal.row], data.wolf_rest_elapsed[animal.row], data.wolf_howl_elapsed[animal.row], data.wolf_howled[animal.row], data.wolf_retreating[animal.row]])
		elif data.identity_kind[animal.row] == AnimalEntity.Kind.SHEEPDOG:
			var anchor_id: int = data.identity_entity_id[data.live(data.dog_protected_sheep[animal.row]).row] if g_gameplayEngine.animal_system.is_live(animal, data.live(data.dog_protected_sheep[animal.row])) else 0
			var stray_id: int = data.identity_entity_id[data.live(data.dog_collected_sheep[animal.row]).row] if g_gameplayEngine.animal_system.is_live(animal, data.live(data.dog_collected_sheep[animal.row])) else 0
			values.append([anchor_id, stray_id, data.dog_protection_center[animal.row], data.dog_guard_point[animal.row], data.dog_patrol_angle[animal.row], data.dog_returning[animal.row]])
	return values

func _verify() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var defaults := load("res://Resources/Gameplay/CFG_Simulation.tres") as SimulationConfig
	var original_size := defaults.arena_size
	for total in [1000, 2000, 3000, 4000]:
		var distribution := defaults.copy_config()
		distribution.initial_total = total
		var counts := distribution.get_initial_counts()
		_check(counts.x + counts.y + counts.z == total, "exact total %d" % total)
		for kind in range(3):
			_check(absf(counts[kind] - float(total) * Vector3i(20, 2, 1)[kind] / 23.0) < 1.0, "species rounding %d/%d" % [total, kind])
		for mode in ["scaled", "fixed"]:
			entities_count = total
			scenario = mode
			var settings := defaults.copy_config()
			_prepare_exact_settings(settings)
			_check(settings.validate().is_empty(), "exact configuration validates %d/%s" % [total, mode])
			var expected_ratio := float(total) / defaults.initial_total if mode == "scaled" else 1.0
			_check(is_equal_approx(settings.arena_size.x * settings.arena_size.y / (original_size.x * original_size.y), expected_ratio), "area scaling %d/%s" % [total, mode])
	_check(defaults.arena_size == original_size, "default resources preserved")
	var tied := defaults.copy_config()
	tied.initial_total = 2
	tied.sheep_ratio = 1.0
	tied.wolf_ratio = 1.0
	tied.sheepdog_ratio = 1.0
	_check(tied.get_initial_counts() == Vector3i(1, 1, 0), "largest remainder ties follow species order")
	entities_count = 0
	scenario = ""
	tiles = 2
	layout = "spread"
	_start()
	engine.set_process(false)
	engine.paused = true
	_check(engine.entity_service.get_counts() == configured_counts, "expanded species counts")
	_check(engine.config.arena_size == original_size * 2.0, "expanded area")
	var entity_count: int = engine.entity_service.entities.size()
	for item: Service in [engine.entity_service, engine.grid_service, engine.debug_service, engine.profile_service]:
		_check(item.started, "service is started")
		item.startup()
	_check(engine.entity_service.entities.size() == entity_count, "repeated startup preserves entities")
	_check(Performance.has_custom_monitor("Simulation/StepMean"), "repeated startup preserves monitor registration")
	engine.debug_service.selected = engine.entity_service.entities[0]
	engine.debug_service.reset()
	_check(engine.debug_service.selected == null, "debug reset releases selected animal")
	var positions: Array[Vector2] = []
	var bounds := Rect2(Vector2.ZERO, engine.config.arena_size)
	var in_bounds := true
	for animal in engine.entity_service.entities:
		positions.append(data.motion_position[animal.row])
		in_bounds = in_bounds and bounds.has_point(data.motion_position[animal.row])
	_check(in_bounds, "spawned animals stay inside arena")
	engine.entity_service.clear()
	engine.rng.seed = engine.config.random_seed
	_spawn_layout(original_size)
	var repeated: Array[Vector2] = []
	for animal in engine.entity_service.entities:
		repeated.append(data.motion_position[animal.row])
	_check(positions == repeated, "layout positions reproduce with fixed seed")
	engine.entity_service.clear()
	layout = "cluster"
	_spawn_layout(original_size)
	var central := Rect2((engine.config.arena_size - original_size) * 0.5, original_size)
	var clustered := true
	for animal in engine.entity_service.entities:
		clustered = clustered and central.has_point(data.motion_position[animal.row])
	_check(clustered and engine.entity_service.entities.size() == configured_counts.x + configured_counts.y + configured_counts.z, "cluster preserves population in one central region")
	engine.entity_service.clear()
	var old_counts := configured_counts
	var small_config := defaults.copy_config()
	small_config.initial_total = 8
	small_config.sheep_ratio = 1.0
	small_config.wolf_ratio = 1.0
	small_config.sheepdog_ratio = 1.0
	configured_counts = small_config.get_initial_counts()
	_spawn_layout(original_size)
	_check(engine.entity_service.get_counts() == Vector3i(3, 3, 2), "tiled layout preserves total and ratios when species counts do not divide evenly")
	engine.entity_service.clear()
	var exact_config := defaults.copy_config()
	exact_config.initial_total = 1000
	configured_counts = exact_config.get_initial_counts()
	_spawn_exact_layout()
	_check(engine.entity_service.get_counts() == configured_counts, "exact layout spawns requested species counts")
	var exact_positions: Array[Vector2] = []
	var exact_bounds := Rect2(Vector2(12, 94), engine.config.arena_size - Vector2(24, 152))
	var exact_inside := true
	for animal in engine.entity_service.entities:
		exact_positions.append(data.motion_position[animal.row])
		exact_inside = exact_inside and exact_bounds.has_point(data.motion_position[animal.row])
	_check(exact_inside, "uniform animal positions inside movement boundaries")
	engine.entity_service.clear()
	_spawn_exact_layout()
	var exact_repeated: Array[Vector2] = []
	for animal in engine.entity_service.entities:
		exact_repeated.append(data.motion_position[animal.row])
	_check(exact_positions == exact_repeated, "uniform layout independent of animal initialization RNG")
	engine.entity_service.clear()
	configured_counts = old_counts
	var service: EntityService = engine.entity_service
	service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(119, 110))
	service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(120, 110))
	service.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400, 110))
	engine.grid_service.rebuild()
	var nearby: PackedInt32Array = engine.grid_service.get_nearby_indices(Vector2(120, 110), 2.0)
	_check(nearby.size() == 2 and engine.grid_service.spatial_candidate_count == 2, "cell boundary query counts broad-phase candidates")
	_check(engine.grid_service.spatial_query_count == 1 and engine.grid_service.spatial_max_candidates == 2, "query statistics")
	_check(engine.grid_service.spatial_nonempty_cells == 3 and engine.grid_service.spatial_max_occupancy == 1, "occupancy statistics")
	_check(engine.grid_service.get_nearby_indices(Vector2(2000, 1000), 1.0).is_empty(), "empty query")
	_check(engine.grid_service.spatial_query_count == 2 and engine.grid_service.spatial_candidate_count == 2, "empty query contributes denominator")
	engine.profile_service.reset()
	engine.profile_service.last_step_ms = 2.0
	engine.grid_service.spatial_query_count = 1
	engine.grid_service.spatial_candidate_count = 10
	engine.grid_service.spatial_nonempty_cells = 3
	engine.grid_service.spatial_max_occupancy = 2
	engine.profile_service._record_performance_step()
	engine.profile_service.last_step_ms = 6.0
	engine.grid_service.spatial_query_count = 3
	engine.grid_service.spatial_candidate_count = 6
	engine.grid_service.spatial_nonempty_cells = 5
	engine.grid_service.spatial_max_occupancy = 4
	engine.profile_service._stats_window_started = Time.get_ticks_usec() - 1000000
	engine.profile_service._record_performance_step()
	_check(Performance.get_custom_monitor("Simulation/StepMean") == 0.004 and Performance.get_custom_monitor("Simulation/StepMax") == 0.006, "window step average and maximum")
	_check(Performance.get_custom_monitor("Spatial/CandidatesPerQuery") == 4.0, "candidate mean weighted by query count")
	_check(Performance.get_custom_monitor("Spatial/QueriesPerStep") == 2.0 and Performance.get_custom_monitor("Spatial/NonemptyCells") == 4.0, "per-step means")
	_check(Performance.get_custom_monitor("Spatial/MaxCellOccupancy") == 4.0, "window occupancy maximum")
	engine._process(1.0 / 60.0)
	_check(engine.step_count == 0 and Performance.get_custom_monitor("Simulation/StepMean") == 0.004, "pause preserves window until next publication")
	engine.profile_service._stats_window_started = Time.get_ticks_usec() - 1000000
	engine.profile_service._process(0.0)
	_check(Performance.get_custom_monitor("Simulation/StepMean") == 0.0, "paused empty window publishes zero")
	engine.profile_service.reset()
	engine.profile_service._stats_window_started = Time.get_ticks_usec() - 1000000
	engine.profile_service._record_performance_step()
	_check(Performance.get_custom_monitor("Spatial/CandidatesPerQuery") == 0.0, "zero-query window is finite zero")
	var debug: DebugService = engine.debug_service
	var hud_calls: int = engine.profile_service.debug_calls["HUDRefresh"]
	debug.hud_enabled = false
	debug._process(0.0)
	_check(engine.profile_service.debug_calls["HUDRefresh"] == hud_calls, "disabled HUD skips debug service refresh")
	debug.hud_enabled = true
	debug._process(0.0)
	_check(engine.profile_service.debug_calls["HUDRefresh"] == hud_calls + 1 and debug.hud.status.text.begins_with("PAUSED"), "debug service refreshes and profiles HUD while paused")
	engine.config.initial_total = 30
	engine.config.sheep_ratio = 24.0
	engine.config.wolf_ratio = 4.0
	engine.config.sheepdog_ratio = 2.0
	engine.profile_service.set_performance_stats_enabled(true)
	engine.reset_simulation()
	engine.paused = true
	for index in range(120):
		engine.simulate_step(1.0 / 60.0)
	var observed := _state()
	var stage_sum: float = 0.0
	for name in engine.profile_service.last_stages_ms:
		stage_sum += engine.profile_service.last_stages_ms[name]
	_check(is_equal_approx(stage_sum, engine.profile_service.last_step_ms), "exclusive stages account for whole measured step")
	var names := Performance.get_custom_monitor_names()
	var types := Performance.get_custom_monitor_types()
	_check(types[names.find("SimStages/SteeringMean")] == Performance.MONITOR_TYPE_TIME, "steering stage registers a time monitor")
	_check(types[names.find("Simulation/StepMean")] == Performance.MONITOR_TYPE_TIME, "step monitor registers native time unit")
	_check(types[names.find("Spatial/QueriesPerStep")] == Performance.MONITOR_TYPE_QUANTITY, "query monitor registers quantity unit")
	engine.profile_service.set_performance_stats_enabled(true, true)
	_check(Performance.has_custom_monitor("Hotspots/WolfTargetMean"), "detailed mode registers hotspots")
	engine.reset_simulation()
	engine.paused = true
	for index in range(120):
		engine.simulate_step(1.0 / 60.0)
	_check(observed == _state(), "detailed timing preserves RNG and animal state")
	_check(engine.profile_service.last_hotspot_calls["NearbyQuery"] > 0, "detailed mode counts queries")
	engine.profile_service.set_performance_stats_enabled(true)
	_check(not Performance.has_custom_monitor("Hotspots/WolfTargetMean"), "stages mode unregisters hotspots")
	engine.profile_service.set_performance_stats_enabled(false)
	_check(not Performance.has_custom_monitor("Simulation/StepMean"), "disable unregisters monitors")
	engine.reset_simulation()
	engine.paused = true
	for index in range(120):
		engine.simulate_step(1.0 / 60.0)
	_check(observed == _state(), "statistics preserve RNG and animal state after equal simulation steps")
	_check(engine.grid_service.spatial_query_count == 0 and engine.grid_service.spatial_max_occupancy == 0, "disabled statistics remain zero")
	engine.profile_service.set_performance_stats_enabled(true)
	engine.reset_simulation()
	_check(Performance.get_custom_monitor("Simulation/StepMean") == 0.0 and engine.grid_service.spatial_query_count == 0, "reset clears counters and monitors")
	engine.debug_service.selected = engine.entity_service.entities[0] if not engine.entity_service.entities.is_empty() else null
	engine.stop_simulation()
	engine.stop_simulation()
	_check(not Performance.has_custom_monitor("Spatial/QueriesPerStep"), "stop unregisters monitors")
	_check(engine.debug_service.selected == null and engine.debug_service.hud == null, "shutdown releases debug references")
	_check(engine.entity_service.entities.is_empty() and engine.entity_service.container == null, "shutdown releases entities and container")
	for item: Service in [engine.entity_service, engine.grid_service, engine.debug_service, engine.profile_service]:
		item.reset()
		_check(not item.started, "reset does not restart stopped service")
	engine.start_simulation(scene.get_node("World"), scene.get_node("DebugHUD"), scene.simulation_config)
	engine.set_process(false)
	engine.paused = true
	_check(Performance.has_custom_monitor("Spatial/QueriesPerStep"), "restart registers monitors again")
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	print("PERFORMANCE_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
