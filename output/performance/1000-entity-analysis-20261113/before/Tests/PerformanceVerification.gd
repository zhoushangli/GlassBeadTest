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
	var values: Array = [engine.rng.state, engine.entity_service.capture_count, engine.grass_bites.duplicate(), engine.grass_claims.duplicate(), engine.grass_regrow_remaining.duplicate()]
	for animal in engine.entity_service.entities:
		var target_id: int = animal.target.entity_id if animal.is_live(animal.target) else 0
		values.append([animal.entity_id, animal.position, animal.velocity, animal.current_behavior, target_id, animal.alive])
		if animal is SheepController:
			values.append([animal.hunger, animal.grass_target_index, animal.meals_eaten, animal.grazing_progress, animal.threat_memory])
		elif animal is WolfController:
			values.append([animal.hunting, animal.capture_progress, animal.hunt_elapsed])
		elif animal is SheepdogController:
			var anchor_id: int = animal.protected_sheep.entity_id if animal.is_live(animal.protected_sheep) else 0
			values.append([anchor_id, animal.protection_center, animal.intercept_point])
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
			var patches := roundi(5.0 * total / 276.0) if mode == "scaled" else 5
			_check(settings.grass.positions.size() == patches, "grass count %d/%s" % [total, mode])
			var margin := Vector2.ONE * settings.grass.patch_radius
			var bounds := Rect2(margin, settings.arena_size - margin * 2.0)
			var inside := true
			for point in settings.grass.positions:
				inside = inside and bounds.has_point(point)
			_check(inside, "grass patch extents inside arena %d/%s" % [total, mode])
	_check(defaults.arena_size == Vector2(1280, 720) and defaults.grass.positions.size() == 5, "default resources preserved")
	_check(_exact_counts(2, Vector3i.ONE) == Vector3i(1, 1, 0), "largest remainder ties follow species order")
	entities_count = 0
	scenario = ""
	tiles = 2
	layout = "spread"
	_start()
	engine.set_physics_process(false)
	engine.paused = true
	_check(engine.entity_service.get_counts() == Vector3i(960, 96, 48), "expanded species counts")
	_check(engine.config.arena_size == Vector2(2560, 1440), "expanded area")
	_check(engine.grass_positions.size() == 480 and engine.config.grass.positions.size() == 20, "grass scales with area")
	var positions: Array[Vector2] = []
	var bounds := Rect2(Vector2.ZERO, engine.config.arena_size)
	var in_bounds := true
	for animal in engine.entity_service.entities:
		positions.append(animal.position)
		in_bounds = in_bounds and bounds.has_point(animal.position)
	_check(in_bounds, "spawned animals stay inside arena")
	var grass_in_bounds := true
	for point in engine.grass_positions:
		grass_in_bounds = grass_in_bounds and bounds.has_point(point)
	_check(grass_in_bounds, "grass stays inside arena")
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
	engine.reset_performance_stats()
	engine.last_step_ms = 2.0
	service.spatial_query_count = 1
	service.spatial_candidate_count = 10
	service.spatial_nonempty_cells = 3
	service.spatial_max_occupancy = 2
	engine._record_performance_step()
	engine.last_step_ms = 6.0
	service.spatial_query_count = 3
	service.spatial_candidate_count = 6
	service.spatial_nonempty_cells = 5
	service.spatial_max_occupancy = 4
	engine._stats_window_started = Time.get_ticks_usec() - 1000000
	engine._record_performance_step()
	_check(Performance.get_custom_monitor("Simulation/StepMeanMs") == 4.0 and Performance.get_custom_monitor("Simulation/StepMaxMs") == 6.0, "window step average and maximum")
	_check(Performance.get_custom_monitor("Spatial/CandidatesPerQuery") == 4.0, "candidate mean weighted by query count")
	_check(Performance.get_custom_monitor("Spatial/QueriesPerStep") == 2.0 and Performance.get_custom_monitor("Spatial/NonemptyCells") == 4.0, "per-step means")
	_check(Performance.get_custom_monitor("Spatial/MaxCellOccupancy") == 4.0, "window occupancy maximum")
	engine._physics_process(1.0 / 60.0)
	_check(engine.step_count == 0 and Performance.get_custom_monitor("Simulation/StepMeanMs") == 4.0, "pause preserves last completed window")
	engine.reset_performance_stats()
	engine._stats_window_started = Time.get_ticks_usec() - 1000000
	engine._record_performance_step()
	_check(Performance.get_custom_monitor("Spatial/CandidatesPerQuery") == 0.0, "zero-query window is finite zero")
	engine.config.initial_sheep = 24
	engine.config.initial_wolves = 4
	engine.config.initial_sheepdogs = 2
	engine.set_performance_stats_enabled(true)
	engine.reset_simulation()
	engine.paused = true
	for index in range(120):
		engine.simulate_step(1.0 / 60.0)
	var observed := _state()
	engine.set_performance_stats_enabled(false)
	_check(not Performance.has_custom_monitor("Simulation/StepMeanMs"), "disable unregisters monitors")
	engine.reset_simulation()
	engine.paused = true
	for index in range(120):
		engine.simulate_step(1.0 / 60.0)
	_check(observed == _state(), "statistics preserve RNG and animal state after equal simulation steps")
	_check(service.spatial_query_count == 0 and service.spatial_max_occupancy == 0, "disabled statistics remain zero")
	engine.set_performance_stats_enabled(true)
	engine.reset_simulation()
	_check(Performance.get_custom_monitor("Simulation/StepMeanMs") == 0.0 and service.spatial_query_count == 0, "reset clears counters and monitors")
	engine.stop_simulation()
	_check(not Performance.has_custom_monitor("Spatial/QueriesPerStep"), "stop unregisters monitors")
	engine.start_simulation(scene.get_node("World"), scene.get_node("DebugHUD"), scene.simulation_config)
	engine.set_physics_process(false)
	engine.paused = true
	_check(Performance.has_custom_monitor("Spatial/QueriesPerStep"), "restart registers monitors again")
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	print("PERFORMANCE_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
