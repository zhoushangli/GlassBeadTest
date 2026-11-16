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
	var values: Array = [engine.rng.state, engine.entity_service.capture_count]
	for animal in engine.entity_service.entities:
		var target_id: int = animal.target.entity_id if animal.is_live(animal.target) else 0
		values.append([animal.entity_id, animal.position, animal.velocity, animal.current_behavior, target_id, animal.alive, animal.facing, animal.last_seen_position, animal.last_seen_velocity, animal.unseen_elapsed])
		if animal is SheepController:
			values.append([animal.has_alert, animal.alert_elapsed, animal.has_panic, animal.panic_elapsed])
		elif animal is WolfController:
			values.append([animal.hunting, animal.hunt_elapsed, animal.charging, animal.strategy, animal.strategy_failures.duplicate(), animal.rest_elapsed, animal.howl_elapsed, animal.howled, animal.retreating])
		elif animal is SheepdogController:
			var anchor_id: int = animal.protected_sheep.entity_id if animal.is_live(animal.protected_sheep) else 0
			var stray_id: int = animal.collected_sheep.entity_id if animal.is_live(animal.collected_sheep) else 0
			values.append([anchor_id, stray_id, animal.protection_center, animal.guard_point, animal.patrol_angle, animal._returning])
	return values

func _verify() -> void:
	var defaults := load("res://Resources/Gameplay/CFG_Simulation.tres") as SimulationConfig
	for total in [1000, 2000, 3000, 4000]:
		var counts := _exact_counts(total, Vector3i(240, 24, 12))
		_check(counts.x + counts.y + counts.z == total, "exact total %d" % total)
		for kind in range(3):
			_check(absf(counts[kind] - float(total) * Vector3i(20, 2, 1)[kind] / 23.0) < 1.0, "species rounding %d/%d" % [total, kind])
		for mode in ["scaled", "fixed"]:
			entities_count = total
			scenario = mode
			var settings := defaults.copy_config()
			_prepare_exact_settings(settings)
			_check(settings.validate().is_empty(), "exact configuration validates %d/%s" % [total, mode])
			var expected_ratio := float(total) / 276.0 if mode == "scaled" else 1.0
			_check(is_equal_approx(settings.arena_size.x * settings.arena_size.y / (1280.0 * 720.0), expected_ratio), "area scaling %d/%s" % [total, mode])
	_check(defaults.arena_size == Vector2(1280, 720), "default resources preserved")
	_check(_exact_counts(2, Vector3i.ONE) == Vector3i(1, 1, 0), "largest remainder ties follow species order")
	entities_count = 0
	scenario = ""
	tiles = 2
	layout = "spread"
	_start()
	engine.set_process(false)
	engine.paused = true
	_check(engine.entity_service.get_counts() == Vector3i(960, 96, 48), "expanded species counts")
	_check(engine.config.arena_size == Vector2(2560, 1440), "expanded area")
	var entity_count: int = engine.entity_service.entities.size()
	for item: Service in [engine.entity_service, engine.debug_service, engine.profile_service]:
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
		positions.append(animal.position)
		in_bounds = in_bounds and bounds.has_point(animal.position)
	_check(in_bounds, "spawned animals stay inside arena")
	engine.entity_service.clear()
	engine.rng.seed = engine.config.random_seed
	_spawn_layout(Vector3i(240, 24, 12), Vector2(1280, 720))
	var repeated: Array[Vector2] = []
	for animal in engine.entity_service.entities:
		repeated.append(animal.position)
	_check(positions == repeated, "layout positions reproduce with fixed seed")
	engine.entity_service.clear()
	layout = "cluster"
	_spawn_layout(Vector3i(240, 24, 12), Vector2(1280, 720))
	var central := Rect2((engine.config.arena_size - Vector2(1280, 720)) * 0.5, Vector2(1280, 720))
	var clustered := true
	for animal in engine.entity_service.entities:
		clustered = clustered and central.has_point(animal.position)
	_check(clustered and engine.entity_service.entities.size() == 1104, "cluster preserves population in one central region")
	engine.entity_service.clear()
	var old_counts := configured_counts
	configured_counts = _exact_counts(1000, Vector3i(240, 24, 12))
	_spawn_exact_layout()
	_check(engine.entity_service.get_counts() == configured_counts, "exact layout spawns requested species counts")
	var exact_positions: Array[Vector2] = []
	var exact_bounds := Rect2(Vector2(12, 94), engine.config.arena_size - Vector2(24, 152))
	var exact_inside := true
	for animal in engine.entity_service.entities:
		exact_positions.append(animal.position)
		exact_inside = exact_inside and exact_bounds.has_point(animal.position)
	_check(exact_inside, "uniform animal positions inside movement boundaries")
	engine.entity_service.clear()
	_spawn_exact_layout()
	var exact_repeated: Array[Vector2] = []
	for animal in engine.entity_service.entities:
		exact_repeated.append(animal.position)
	_check(exact_positions == exact_repeated, "uniform layout independent of animal initialization RNG")
	engine.entity_service.clear()
	configured_counts = old_counts
	var service: EntityService = engine.entity_service
	service.spawn(AnimalController.Kind.SHEEP, 1, Vector2(119, 110))
	service.spawn(AnimalController.Kind.SHEEP, 1, Vector2(120, 110))
	service.spawn(AnimalController.Kind.WOLF, 1, Vector2(400, 110))
	service.rebuild_spatial_index()
	var nearby := service.get_nearby_indices(Vector2(120, 110), 2.0)
	_check(nearby.size() == 2 and service.spatial_candidate_count == 2, "cell boundary query counts broad-phase candidates")
	_check(service.spatial_query_count == 1 and service.spatial_max_candidates == 2, "query statistics")
	_check(service.spatial_nonempty_cells == 3 and service.spatial_max_occupancy == 1, "occupancy statistics")
	_check(service.get_nearby_indices(Vector2(2000, 1000), 1.0).is_empty(), "empty query")
	_check(service.spatial_query_count == 2 and service.spatial_candidate_count == 2, "empty query contributes denominator")
	engine.profile_service.reset()
	engine.profile_service.last_step_ms = 2.0
	service.spatial_query_count = 1
	service.spatial_candidate_count = 10
	service.spatial_nonempty_cells = 3
	service.spatial_max_occupancy = 2
	engine.profile_service._record_performance_step()
	engine.profile_service.last_step_ms = 6.0
	service.spatial_query_count = 3
	service.spatial_candidate_count = 6
	service.spatial_nonempty_cells = 5
	service.spatial_max_occupancy = 4
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
	engine.config.initial_sheep = 24
	engine.config.initial_wolves = 4
	engine.config.initial_sheepdogs = 2
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
	_check(service.spatial_query_count == 0 and service.spatial_max_occupancy == 0, "disabled statistics remain zero")
	engine.profile_service.set_performance_stats_enabled(true)
	engine.reset_simulation()
	_check(Performance.get_custom_monitor("Simulation/StepMean") == 0.0 and service.spatial_query_count == 0, "reset clears counters and monitors")
	engine.debug_service.selected = engine.entity_service.entities[0] if not engine.entity_service.entities.is_empty() else null
	engine.stop_simulation()
	engine.stop_simulation()
	_check(not Performance.has_custom_monitor("Spatial/QueriesPerStep"), "stop unregisters monitors")
	_check(engine.debug_service.selected == null and engine.debug_service.hud == null, "shutdown releases debug references")
	_check(engine.entity_service.entities.is_empty() and engine.entity_service.container == null, "shutdown releases entities and container")
	for item: Service in [engine.entity_service, engine.debug_service, engine.profile_service]:
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
