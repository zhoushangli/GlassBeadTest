extends SceneTree

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node
var authored: Resource
var verification_directory: String

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _empty(frozen: bool = true) -> void:
	engine.config = authored.copy_config()
	engine.config.initial_total = 0
	engine.config.perception_interval = 0.0
	if frozen:
		engine.config.sheep.move_speed = 0.0
		engine.config.sheep.flee_speed = 0.0
		engine.config.wolf.move_speed = 0.0
		engine.config.wolf.chase_speed = 0.0
		engine.config.wolf.retreat_speed = 0.0
		engine.config.sheepdog.move_speed = 0.0
		engine.config.sheepdog.drive_speed = 0.0
		engine.config.sheepdog.return_speed = 0.0
	engine.reset_simulation()
	engine.paused = true

func _animal(kind: AnimalEntity.Kind, point: Vector2) -> AnimalEntity:
	return engine.entity_service.spawn(kind, 1, point)[0]

func _step(count: int) -> void:
	for index in range(count):
		engine.job_service.invalidate_async()
		engine.grid_service.rebuild()
		for kind in [AnimalEntity.Kind.WOLF, AnimalEntity.Kind.SHEEPDOG]:
			engine._decision_elapsed[kind] = 1.0
		engine._submit_decisions(0.0)
		for job: Job in engine.job_service.async_jobs.values():
			while job.state == Job.State.WORKING and not WorkerThreadPool.is_task_completed(job.task_id):
				OS.delay_msec(1)
		engine.simulate_step(1.0 / 60.0)
		engine.job_service.invalidate_async()

func _key(code: Key, shift: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.shift_pressed = shift
	event.echo = echo
	engine.debug_service._unhandled_input(event)

func _verify_resources_and_vision() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	_check(authored.validate().is_empty(), "authored CFG validates")

	var copy: SimulationConfig = authored.copy_config()
	copy.sheep.move_speed = 19.0
	_check(authored.sheep.move_speed == 70.0, "runtime resources are independent")

	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(400, 300))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300))
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(400, 300))
	for animal in [sheep, wolf, dog]:
		if animal == sheep:
			_check(data.brain_player[animal.row] == null, "sheep has no behavior tree")
		else:
			_check(data.brain_player[animal.row].get_bt_instance() != null and data.brain_player[animal.row].update_mode == BTPlayer.MANUAL, "manual behavior tree is instantiated")
		data.motion_facing[animal.row] = Vector2.RIGHT
		if data.identity_kind[animal.row] != AnimalEntity.Kind.SHEEP:
			var radius: float = data.settings[animal.row].perception_radius
			var half: float = deg_to_rad(data.settings[animal.row].vision_angle * 0.5)
			_check(g_gameplayEngine.animal_system.can_see(animal, data.motion_position[animal.row]), "coincident target visible")
			_check(g_gameplayEngine.animal_system.can_see(animal, data.motion_position[animal.row] + Vector2.RIGHT * radius), "range boundary visible")
			_check(not g_gameplayEngine.animal_system.can_see(animal, data.motion_position[animal.row] + Vector2.RIGHT * (radius + 1.0)), "outside visual range rejected")
			_check(g_gameplayEngine.animal_system.can_see(animal, data.motion_position[animal.row] + Vector2.from_angle(half) * 50.0), "angle boundary visible")
			_check(not g_gameplayEngine.animal_system.can_see(animal, data.motion_position[animal.row] + Vector2.from_angle(half + 0.01) * 50.0), "outside visual angle rejected")
		data.motion_velocity[animal.row] = Vector2.ZERO
		data.motion_desired_velocity[animal.row] = Vector2.ZERO
		data.motion_separation[animal.row] = Vector2.ZERO
		data.motion_speed_limit[animal.row] = 0.0
		g_gameplayEngine.animal_system.update_movement(1.0 / 60.0)
		_check(data.motion_facing[animal.row] == Vector2.RIGHT, "stationary facing retained")
	data.motion_desired_velocity[wolf.row] = Vector2.DOWN * 50.0
	data.motion_speed_limit[wolf.row] = 50.0
	g_gameplayEngine.animal_system.update_movement(1.0 / 60.0)
	engine.render_service.sync()
	_check(data.motion_facing[wolf.row].is_equal_approx(Vector2.DOWN) and is_equal_approx(absf(_render_transform(wolf).get_rotation()), PI), "sprite and facing follow actual movement")

	engine.debug_service.select_at(data.motion_position[sheep.row])
	engine.entity_service.capture(sheep)
	_check(not data.identity_alive[sheep.row] and not engine.entity_service.capture(sheep), "death is idempotent")

	_step(20)
	_check(not engine.entity_service.entities.has(sheep), "corpse removed from registry")

func _verify_population_config() -> void:
	var settings: SimulationConfig = authored.copy_config()
	var cases := [
		[276, 20.0, 2.0, 1.0, Vector3i(240, 24, 12)],
		[100, 0.8, 0.1, 0.1, Vector3i(80, 10, 10)],
		[100, 80.0, 10.0, 10.0, Vector3i(80, 10, 10)],
		[0, 0.0, 0.0, 0.0, Vector3i.ZERO],
		[1, 1.0, 1.0, 1.0, Vector3i(1, 0, 0)],
		[2, 1.0, 1.0, 1.0, Vector3i(1, 1, 0)],
		[7, 0.0, 1.0, 1.0, Vector3i(0, 4, 3)],
		[30, 24.0, 4.0, 2.0, Vector3i(24, 4, 2)],
		[30000, 0.1, 0.2, 0.7, Vector3i(3000, 6000, 21000)],
	]
	for sample in cases:
		settings.initial_total = sample[0]
		settings.sheep_ratio = sample[1]
		settings.wolf_ratio = sample[2]
		settings.sheepdog_ratio = sample[3]
		var counts := settings.get_initial_counts()
		_check(settings.validate().is_empty() and counts == sample[4], "relative population allocation %s" % str(sample))
		_check(counts.x + counts.y + counts.z == settings.initial_total, "integer population allocation preserves total")
	settings.initial_total = 1
	settings.sheep_ratio = 0.0
	settings.wolf_ratio = 0.0
	settings.sheepdog_ratio = 0.0
	_check(not settings.validate().is_empty(), "nonzero population rejects all-zero ratios")

	settings.sheep_ratio = -1.0
	_check(not settings.validate().is_empty(), "negative ratios rejected")

	settings.sheep_ratio = NAN
	_check(not settings.validate().is_empty(), "nonfinite ratios rejected")

	settings = authored.copy_config()
	var previous := settings.copy_config()
	settings.initial_total += 1
	_check(settings.requires_restart(previous), "total changes require restart")

	settings.initial_total = previous.initial_total
	settings.wolf_ratio += 1.0
	_check(settings.requires_restart(previous), "ratio changes require restart")

func _verify_sheep() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(400, 300)) as AnimalEntity
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(300, 300)) as AnimalEntity
	data.motion_facing[sheep.row] = Vector2.RIGHT
	data.wolf_resting[wolf.row] = int(true)
	data.wolf_rest_elapsed[wolf.row] = -100.0
	_step(1)
	_check(maxf(data.sheep_threat_strength[sheep.row], data.sheep_panic_strength[sheep.row]) > 0.0, "wolf behind sheep causes omnidirectional pressure")

	data.motion_position[wolf.row] = Vector2(380, 300)
	_step(1)
	_check(maxf(data.sheep_threat_strength[sheep.row], data.sheep_panic_strength[sheep.row]) > 0.0, "nearby wolf causes flight without vision")

	data.motion_position[wolf.row] = Vector2(100, 500)
	_step(1)
	_check(data.sheep_threat_strength[sheep.row] == 0.0, "lost threat immediately clears direct pressure")

	g_gameplayEngine.sheep_system.receive_howl(sheep, Vector2(350, 300))
	_step(1)
	_check(maxf(data.sheep_threat_strength[sheep.row], data.sheep_panic_strength[sheep.row]) > 0.0, "howl causes continuous panic")

	data.sheep_panic_strength[sheep.row] = 0.5
	g_gameplayEngine.sheep_system.receive_howl(sheep, Vector2(350, 300))
	_check(data.sheep_panic_strength[sheep.row] == 1.0, "repeated howl refreshes panic")

	engine.config.sheep.panic_duration = 0.01
	_step(1)
	_check(data.sheep_panic_strength[sheep.row] == 0.0, "panic decays to zero without alert state")

	_empty(false)
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(400, 300)) as AnimalEntity
	var neighbor := _animal(AnimalEntity.Kind.SHEEP, Vector2(440, 300))
	data.motion_velocity[neighbor.row] = Vector2.DOWN * 20.0
	engine.grid_service.rebuild()
	data.motion_velocity[neighbor.row] = Vector2.UP * 20.0
	g_gameplayEngine.sheep_system.perceive(sheep, 1.0 / 60.0)
	_check(data.sheep_neighbor_count[sheep.row] == 1 and data.sheep_alignment[sheep.row].y > 0.0, "BOID reads snapshot velocity")

	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(350, 300))
	engine.grid_service.rebuild()
	g_gameplayEngine.dog_system.accumulate_sheep_pressure()
	g_gameplayEngine.sheep_system.perceive(sheep, 1.0 / 60.0)
	g_gameplayEngine.animal_system.decide(sheep, 1.0 / 60.0)
	g_gameplayEngine.animal_system.update_steering(1.0 / 60.0)
	_check(data.sheep_dog_pressure[sheep.row].length() > 0.0 and data.motion_desired_velocity[sheep.row].x > 0.0, "dog pushes sheep away")

	data.motion_position[dog.row] = Vector2(100, 500)

func _verify_continuous_sheep() -> void:
	_empty(false)
	var data: AnimalData = engine.entity_service.data
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300))
	engine.config.sheep.wander_weight = 0.0
	engine.config.sheep.cohesion_weight = 0.0
	engine.config.sheep.alignment_weight = 0.0
	engine.grid_service.rebuild()
	engine.wolf_system.accumulate_sheep_pressure()
	var far := data.sheep_threat_strength[sheep.row]
	data.motion_position[wolf.row] = Vector2(450, 300)
	engine.grid_service.rebuild()
	engine.wolf_system.accumulate_sheep_pressure()
	var near := data.sheep_threat_strength[sheep.row]
	_check(near > far, "closer wolf continuously increases pressure")

	data.wolf_hunting[wolf.row] = 1
	engine.wolf_system.accumulate_sheep_pressure()
	_check(is_equal_approx(data.sheep_threat_strength[sheep.row], minf(1.0, near * engine.config.sheep.hunting_pressure_multiplier)), "hunting multiplier strengthens local pressure")

	data.sheep_threat_strength[sheep.row] = 1.0
	data.sheep_threat_direction[sheep.row] = Vector2.LEFT
	data.sheep_dog_pressure[sheep.row] = Vector2.RIGHT
	engine.sheep_system.update_steering(1.0)
	_check(data.motion_desired_velocity[sheep.row].x < 0.0 and data.motion_speed_limit[sheep.row] == engine.config.sheep.flee_speed, "maximum danger suppresses opposing dog pressure and selects escape speed")

	data.sheep_threat_direction[sheep.row] = Vector2.ZERO
	engine.sheep_system.update_steering(1.0)
	_check(not data.motion_desired_velocity[sheep.row].is_zero_approx(), "opposed threats retain deterministic escape")

	engine.sheep_system.receive_howl(sheep, Vector2(450, 300))
	engine.sheep_system.perceive(sheep, engine.config.sheep.panic_duration * 0.5)
	_check(is_equal_approx(data.sheep_panic_strength[sheep.row], 0.5), "panic decays linearly in simulation time")

	var draft: SimulationConfig = engine.config.copy_config()
	draft.sheep.panic_duration = 0.0
	engine.request_config_apply(draft)
	engine._process(0.0)
	_check(data.sheep_panic_strength[sheep.row] == 0.0, "paused hot apply of zero duration clears panic immediately")

	engine.sheep_system.receive_howl(sheep, Vector2(450, 300))
	_check(data.sheep_panic_strength[sheep.row] == 0.0, "zero duration ignores howl panic")

	for key in ["Sheep.wander_weight", "Sheep.hunting_pressure_multiplier"]:
		_check(scene.hud.parameters.editors.has(key), "continuous sheep parameter is exposed: " + key)

func _verify_grid_and_pressure() -> void:
	_empty()
	engine.config.arena_size = Vector2(1280, 720)
	engine.config.grid_cell_size = 30
	var data: AnimalData = engine.entity_service.data
	var grid: GridService = engine.grid_service
	grid.rebuild()
	_check(grid.members.is_empty() and grid.get_nearby_indices(Vector2(300, 300), 10.0).is_empty(), "empty grid queries are safe")

	var first := _animal(AnimalEntity.Kind.SHEEP, Vector2(299, 300))
	var second := _animal(AnimalEntity.Kind.SHEEP, Vector2(300, 300))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(300, 300))
	data.motion_velocity[first.row] = Vector2(10, 0)
	data.motion_velocity[second.row] = Vector2(0, 20)
	grid.rebuild()
	_check(grid.width == 43 and grid.height == 24, "grid dimensions round up at 30 pixels")
	_check(grid.row_cells[second.row] == 10 * grid.width + 10, "flat index uses integer cell coordinates")

	var candidates := grid.get_nearby_indices(Vector2(300, 300), 1.0, AnimalEntity.Kind.SHEEP)
	_check(candidates.size() == 2 and candidates.has(first.row) and candidates.has(second.row) and not candidates.has(wolf.row), "species ranges cross cell boundaries without duplicates")
	_check(grid.cell_offsets[grid.cell_offsets.size() - 1] == 3, "packed ranges cover each active row")
	_check(grid.get_nearby_indices(Vector2(-100, -100), 1.0).is_empty() and grid.get_nearby_indices(Vector2(2000, 1000), 1.0).is_empty(), "outside queries do not wrap grid rows")
	_check(grid.cell_at(Vector2.ZERO) == 0 and grid.cell_at(engine.config.arena_size) == grid.width * grid.height - 1, "boundary cell mapping is clamped")

	engine.sheep_system._scan_neighbors(first, grid)
	_check(data.sheep_neighbor_count[first.row] == 1 and data.sheep_local_flock_center[first.row] == Vector2(300, 300), "shared flock sums exclude the reader")
	_check(data.sheep_alignment[first.row] == Vector2(0, 20), "shared alignment sums exclude the reader velocity")
	_check(grid.sheep_center(Vector2(300, 300), 60.0) == Vector2(299.5, 300), "protection center is weighted by sheep counts")

	engine.config.sheep.flock_radius = 1.0
	engine.config.sheep.alignment_radius = 1.0
	grid.rebuild()
	engine.sheep_system._scan_neighbors(first, grid)
	_check(data.sheep_neighbor_count[first.row] == 0 and data.sheep_alignment[first.row] == Vector2.ZERO, "hot radius changes refresh shared stencils")

	var old_uid := first.uid
	engine.entity_service.capture(first)
	engine.entity_service.remove_expired(1.0)
	grid.rebuild()
	_check(grid.members.size() == 2 and grid.get_nearby_indices(Vector2(300, 300), 1.0, AnimalEntity.Kind.SHEEP).size() == 1, "death and row swaps rebuild correct membership")

	var replacement := _animal(AnimalEntity.Kind.SHEEP, Vector2(330, 300))
	grid.rebuild()
	_check(data.live(first) == null and replacement.uid != old_uid and grid.members.size() == 3, "slot reuse does not resurrect grid identities")

	engine.entity_service.clear()
	_check(grid.members.is_empty() and grid.width == 0, "entity clear releases the spatial snapshot")

	_empty()
	_animal(AnimalEntity.Kind.SHEEP, Vector2(300, 300))
	_animal(AnimalEntity.Kind.SHEEP, Vector2(310, 300))
	_animal(AnimalEntity.Kind.SHEEP, Vector2(340, 300))
	grid.rebuild()
	_check(grid.sheep_center(Vector2(320, 300), 90.0).is_equal_approx(Vector2(950.0 / 3.0, 300)), "protection center weights occupied cells by sheep count")

	_empty()
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(420, 300))
	var left := _animal(AnimalEntity.Kind.WOLF, Vector2(370, 300))
	var right := _animal(AnimalEntity.Kind.WOLF, Vector2(470, 300))
	for source in [left, right]:
		data.wolf_resting[source.row] = 1
		data.wolf_rest_elapsed[source.row] = -100.0
	_animal(AnimalEntity.Kind.SHEEPDOG, Vector2(420, 250))
	grid.rebuild()
	engine.wolf_system.accumulate_sheep_pressure()
	engine.dog_system.accumulate_sheep_pressure()
	_check(data.sheep_threat_direction[sheep.row].is_zero_approx() and data.sheep_threat_strength[sheep.row] != 0, "opposed wolves cancel force but retain danger")
	_check(data.sheep_dog_pressure[sheep.row].is_equal_approx(Vector2(0, 1.0 - 50.0 / 90.0)), "dog pressure has its own distance-weighted channel")

	_step(1)
	_check(maxf(data.sheep_threat_strength[sheep.row], data.sheep_panic_strength[sheep.row]) > 0.0 and data.motion_desired_velocity[sheep.row].is_finite(), "canceled wolf pressure retains finite steering")

	data.motion_position[right.row] = Vector2(320, 300)
	_step(1)
	_check(data.sheep_threat_direction[sheep.row].is_equal_approx(Vector2(2.0 - 150.0 / engine.config.sheep.wolf_pressure_distance, 0)), "multiple wolves add linear distance contributions")

	_step(1)
	_check(data.sheep_threat_direction[sheep.row].is_equal_approx(Vector2(2.0 - 150.0 / engine.config.sheep.wolf_pressure_distance, 0)), "pressure is cleared each step instead of accumulating over time")

	data.motion_position[left.row] = Vector2(100, 500)
	data.motion_position[right.row] = Vector2(100, 500)
	_step(1)
	_check(data.sheep_threat_strength[sheep.row] == 0 and data.sheep_threat_direction[sheep.row].is_zero_approx(), "departed wolves leave no pressure")

	data.motion_position[left.row] = Vector2(420, 300)
	_step(1)
	_check(data.sheep_threat_strength[sheep.row] != 0 and data.sheep_threat_direction[sheep.row].is_finite(), "coincident wolf pressure remains finite and threatening")

	data.motion_position[left.row] = Vector2(420 - engine.config.sheep.wolf_pressure_distance, 300)
	_step(1)
	_check(data.sheep_threat_strength[sheep.row] == 0, "linear wolf pressure reaches zero at its distance boundary")

	data.motion_position[left.row].x -= 1.0
	_step(1)
	_check(data.sheep_threat_strength[sheep.row] == 0, "wolf pressure excludes points beyond its distance")

func _verify_wolves() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(550, 300))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	_step(1)
	_check(data.wolf_hunting[wolf.row] and data.live(data.memory_target[wolf.row]) == sheep and data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.STALK, "visible nearest sheep starts stalk")

	data.wolf_strategy[wolf.row] = AnimalEntity.Strategy.FRONTAL
	var seen := data.memory_last_seen_position[wolf.row]
	data.motion_position[sheep.row] = Vector2(300, 350)
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.SEARCH and data.memory_last_seen_position[wolf.row] == seen and data.motion_movement_goal[wolf.row] == seen, "hidden prey only updates unseen timer")

	data.motion_position[sheep.row] = Vector2(550, 310)
	_step(1)
	_check(data.memory_target_visible[wolf.row] and data.memory_unseen_elapsed[wolf.row] <= 1.0 / 60.0 and data.memory_last_seen_position[wolf.row] == data.motion_position[sheep.row], "reacquired prey refreshes memory without losing snapshot age")

	data.motion_position[sheep.row] = Vector2(300, 350)
	engine.config.wolf.memory_duration = 0.02
	_step(2)
	_check(not data.wolf_hunting[wolf.row] and data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.REST and data.wolf_strategy_failures[wolf.row][0] > 0.9, "lost memory fails hunt once and rests")

	var failures_before: float = data.wolf_strategy_failures[wolf.row][0]
	g_gameplayEngine.wolf_system.end_hunt(wolf, false)
	_check(data.wolf_strategy_failures[wolf.row][0] == failures_before, "failure feedback is idempotent")

	engine.config.wolf.rest_duration = 0.01
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.PATROL, "rest ends into patrol without visible prey")

	_empty()
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(420, 300))
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	_step(1)
	_check(not data.identity_alive[sheep.row] and engine.entity_service.capture_count == 1 and data.wolf_resting[wolf.row], "charge immediately captures in range and rests")

	_empty()
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(420, 300))
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	var second := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[second.row] = Vector2.RIGHT
	_step(1)
	_check(engine.entity_service.capture_count == 1, "multiple wolves cannot double capture")

	_empty()
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(420, 300))
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	g_gameplayEngine.wolf_system.begin_hunt(wolf, sheep)
	data.brain_current_behavior[wolf.row] = AnimalEntity.Behavior.CHASE
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(380, 300))
	g_gameplayEngine.wolf_system.resolve_interactions(wolf, 0.0)
	_check(data.identity_alive[sheep.row] and not data.wolf_hunting[wolf.row] and data.wolf_retreating[wolf.row], "post-movement dog interrupts capture from behind")

	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.RETREAT, "tree prioritizes retreat")

	data.motion_position[dog.row] = Vector2(100, 500)
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.REST and not data.wolf_retreating[wolf.row], "cleared retreat starts rest")

	_empty()
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(550, 300))
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	g_gameplayEngine.wolf_system.begin_hunt(wolf, sheep)
	data.wolf_strategy[wolf.row] = AnimalEntity.Strategy.HOWL
	_step(1)
	_check(data.wolf_howled[wolf.row] and data.sheep_panic_strength[(sheep as AnimalEntity).row] == 1.0 and data.sheep_threat_strength[sheep.row] == 0.0, "howl is delivered after decisions")

	_step(1)
	_check(maxf(data.sheep_threat_strength[sheep.row], data.sheep_panic_strength[sheep.row]) > 0.0, "howl strength decays on the next simulation step")

	var elapsed: float = data.sheep_panic_strength[(sheep as AnimalEntity).row]
	_step(1)
	_check(data.sheep_panic_strength[(sheep as AnimalEntity).row] < elapsed, "one hunt does not howl repeatedly")

	g_gameplayEngine.wolf_system.end_hunt(wolf, true)
	_check(data.wolf_strategy_failures[wolf.row][AnimalEntity.Strategy.HOWL] == 0.0, "success feedback stays nonnegative")

func _verify_dogs() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	var anchor := _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300)) as AnimalEntity
	var stray := _animal(AnimalEntity.Kind.SHEEP, Vector2(680, 300)) as AnimalEntity
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(600, 300)) as AnimalEntity
	data.dog_protected_sheep[dog.row] = anchor
	data.dog_assignment_remaining[dog.row] = 100.0
	data.motion_facing[dog.row] = Vector2.RIGHT
	_step(1)
	_check(data.live(data.dog_collected_sheep[dog.row]) == stray and data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.COLLECT, "local stray is collected")
	_check(data.motion_movement_goal[dog.row].x > data.motion_position[stray.row].x, "collect point is outside stray relative to flock")

	data.motion_position[stray.row] = Vector2(570, 300)
	_step(1)
	_check(data.live(data.dog_collected_sheep[dog.row]) == null and data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.PATROL, "collected sheep releases task")

	var guard := data.dog_guard_point[dog.row]
	_step(1)
	_check(data.dog_guard_point[dog.row] != guard, "patrol target rotates over simulation time")

	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(700, 300)) as AnimalEntity
	data.wolf_resting[wolf.row] = int(true)
	data.wolf_rest_elapsed[wolf.row] = -100.0
	_step(1)
	_check(data.live(data.memory_target[dog.row]) == wolf and data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.DRIVE, "visible nearby wolf interrupts patrol")

	var seen := data.memory_last_seen_position[dog.row]
	data.motion_position[wolf.row] = Vector2(300, 500)
	_step(1)
	_check(data.live(data.memory_target[dog.row]) == wolf and data.memory_last_seen_position[dog.row] == seen and data.motion_movement_goal[dog.row] == seen, "dog pursues last visible position")

	engine.config.sheepdog.memory_duration = 0.02
	_step(2)
	_check(data.live(data.memory_target[dog.row]) == null and data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.RETURN, "dog returns when memory expires")

	data.motion_position[dog.row] = Vector2(1000, 300)
	_step(1)
	_check(data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.RETURN, "leash takes priority")

	_empty()
	anchor = _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300)) as AnimalEntity
	dog = _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(580, 300)) as AnimalEntity
	var other := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(580, 300)) as AnimalEntity
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(670, 300)) as AnimalEntity
	data.wolf_resting[wolf.row] = int(true)
	data.wolf_rest_elapsed[wolf.row] = -100.0
	for item in [dog, other]:
		data.dog_protected_sheep[item.row] = anchor
		data.dog_assignment_remaining[item.row] = 100.0
		data.motion_facing[item.row] = Vector2.RIGHT
	_step(1)
	_check(data.live(data.memory_target[dog.row]) == wolf and data.live(data.memory_target[other.row]) == null, "equal distance wolf claim uses lower dog ID")

	engine.entity_service.dog_rows.reverse()
	_step(1)
	_check(data.live(data.memory_target[dog.row]) == wolf and data.live(data.memory_target[other.row]) == null, "wolf claim independent of dog registry order")

	data.motion_position[wolf.row] = Vector2(100, 500)
	data.memory_target[dog.row] = null
	data.memory_target[other.row] = null
	stray = _animal(AnimalEntity.Kind.SHEEP, Vector2(700, 300)) as AnimalEntity
	_step(1)
	_check(data.live(data.dog_collected_sheep[dog.row]) == stray and data.live(data.dog_collected_sheep[other.row]) == null, "stray gets one responsible dog")

	_empty()
	dog = _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(400, 300)) as AnimalEntity
	_step(1)
	_check(data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.PATROL and data.live(data.memory_target[dog.row]) == null, "no sheep falls back to wandering")

func _verify_behavior_edges() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(470, 300))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.CHASE, "close prey enters charge")

	data.motion_position[sheep.row] = Vector2(550, 300)
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.CHASE, "charge persists when prey moves farther away")

	data.wolf_hunt_elapsed[wolf.row] = engine.config.wolf.hunt_duration
	_step(1)
	_check(not data.wolf_hunting[wolf.row] and data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.REST, "hunt timeout interrupts charge")

	_empty()
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(550, 300))
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	var nearer := _animal(AnimalEntity.Kind.SHEEP, Vector2(530, 300))
	_step(1)
	_check(data.live(data.memory_target[wolf.row]) == nearer, "nearest visible sheep selected")

	engine.entity_service.capture(nearer)
	_step(1)
	_check(not data.wolf_hunting[wolf.row] and data.wolf_resting[wolf.row], "target death ends hunt immediately")

	data.wolf_strategy_failures[wolf.row] = Vector4(1000.0, 0.0, 1000.0, 1000.0)
	var sides: int = 0
	for index in range(200):
		g_gameplayEngine.wolf_system.begin_hunt(wolf, sheep)
		if data.wolf_strategy[wolf.row] == AnimalEntity.Strategy.SIDE:
			sides += 1
	_check(sides > 190, "feedback strongly favors the strategy with fewer failures")

	g_gameplayEngine.wolf_system.end_hunt(wolf, false)
	data.wolf_strategy_failures[wolf.row][0] = 2.0
	var before: float = data.wolf_strategy_failures[wolf.row][0]
	_step(1)
	_check(data.wolf_strategy_failures[wolf.row][0] < before, "strategy failures decay with simulation time")

	_empty(false)
	engine.config.sheep.idle_speed_scale = 0.0
	engine.config.sheep.wander_weight = 0.0
	engine.config.sheep.alignment_weight = 0.0
	engine.config.sheep.cohesion_weight = 0.0
	var anchor := _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300)) as AnimalEntity
	var stray := _animal(AnimalEntity.Kind.SHEEP, Vector2(680, 300)) as AnimalEntity
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(755, 300)) as AnimalEntity
	data.dog_protected_sheep[dog.row] = anchor
	data.dog_assignment_remaining[dog.row] = 1000.0
	var collected := false
	for index in range(1200):
		_step(1)
		if data.motion_position[anchor.row].distance_to(data.motion_position[stray.row]) < engine.config.sheepdog.local_flock_radius:
			collected = true
			break
	_check(collected, "dog pressure actually brings a stray back to local companions")

	_empty()
	anchor = _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300)) as AnimalEntity
	dog = _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(600, 300)) as AnimalEntity
	var other := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(600, 300)) as AnimalEntity
	var first := _animal(AnimalEntity.Kind.WOLF, Vector2(650, 280)) as AnimalEntity
	var second := _animal(AnimalEntity.Kind.WOLF, Vector2(650, 320)) as AnimalEntity
	for predator in [first, second]:
		data.wolf_resting[predator.row] = int(true)
		data.wolf_rest_elapsed[predator.row] = -100.0
	for guard in [dog, other]:
		data.motion_facing[guard.row] = Vector2.RIGHT
		data.dog_protected_sheep[guard.row] = anchor
		data.dog_assignment_remaining[guard.row] = 100.0
	_step(1)
	_check(data.live(data.memory_target[dog.row]) == first and data.live(data.memory_target[other.row]) == second, "loser of shared wolf claim takes remaining threat")

func _verify_runtime_config() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(400, 300)) as AnimalEntity
	g_gameplayEngine.sheep_system.receive_howl(sheep, Vector2(300, 300))
	_step(1)
	var panel: RuntimeConfigPanel = scene.hud.parameters
	panel.set_draft(engine.config)
	_check(panel.editors.has("Sheep.alignment_weight") and panel.editors.has("Wolves.howl_radius") and panel.editors.has("Dogs.vision_angle"), "new CFG fields exposed")
	_check(panel.editors.has("World.grid_cell_size") and panel.editors.has("Sheep.wolf_pressure_distance") and not panel.editors.has("Sheep.vision_angle") and not panel.editors.has("Sheep.emergency_distance"), "pressure and grid settings replace sheep FOV controls")
	_check(not engine.debug_service.visual_options.has("sheep_vision") and not scene.hud.debug_panel.controls.has("sheep_vision"), "sheep vision overlay is removed")

	var draft: SimulationConfig = engine.config.copy_config()
	draft.grid_cell_size = 0
	_check(not draft.validate().is_empty(), "invalid grid size rejected")

	draft = engine.config.copy_config()
	draft.sheepdog.guard_distance = draft.sheepdog.leash_distance
	_check(not draft.validate().is_empty(), "invalid leash rejected")

	draft = engine.config.copy_config()
	draft.sheepdog.collect_distance = draft.sheep.herding_distance
	_check(not draft.validate().is_empty(), "collect point must exert sheep pressure")

	draft = engine.config.copy_config()
	draft.sheep.wolf_pressure_distance = 250.0
	var elapsed := data.sheep_panic_strength[sheep.row]
	_check(engine.request_config_apply(draft).is_empty(), "ordinary config accepted")

	engine._process(0.0)
	_check(data.settings[sheep.row].wolf_pressure_distance == 250.0 and data.sheep_panic_strength[sheep.row] == elapsed and engine.paused, "paused hot apply preserves timers")

	var path := verification_directory.path_join("preset_v6.tres")
	_check(engine.save_preset(path) == OK and engine.load_preset(path) != null, "new preset round trip")

	var old: SimulationConfig = engine.config.copy_config()
	old.preset_version = 5
	var old_path := verification_directory.path_join("preset_old.tres")
	ResourceSaver.save(old, old_path)
	var before := FileAccess.get_file_as_string(old_path)
	_check(engine.load_preset(old_path) == null and FileAccess.get_file_as_string(old_path) == before, "old preset rejected unchanged")

	draft = engine.config.copy_config()
	draft.initial_total = 1
	draft.arena_size = Vector2(1400, 800)
	engine.request_config_apply(draft)
	engine._process(0.0)
	_check(engine.paused and engine.entity_service.get_counts() == Vector3i(1, 0, 0), "restart preserves pause and uses new counts")
	_check(scene.get_node("Camera2D").position == Vector2(700, 400), "arena refresh independent of removed food system")

	draft = engine.config.copy_config()
	draft.grid_cell_size = 60
	engine.request_config_apply(draft)
	engine._process(0.0)
	_check(engine.paused and engine.step_count == 0 and engine.config.grid_cell_size == 60, "grid sizing restarts and preserves pause")

	_step(1)
	_check(engine.grid_service.cell_size == 60.0, "restarted grid uses applied cell size")

	draft = engine.config.copy_config()
	draft.initial_total = 10
	draft.sheep_ratio = 1.0
	draft.wolf_ratio = 1.0
	draft.sheepdog_ratio = 0.0
	engine.request_config_apply(draft)
	engine._process(0.0)
	_check(engine.paused and engine.step_count == 0 and engine.entity_service.get_counts() == Vector3i(5, 5, 0), "total and ratios restart into exact species counts while paused")

	panel.set_draft(engine.config)
	panel.editors["World.wolf_ratio"].value = 0.0
	_check(panel.apply_button.text == "Apply & restart" and panel.message.text.contains("10 sheep, 0 wolves, 0 dogs"), "ratio edits preview allocated counts and require restart")

func _verify_controls() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	_key(KEY_1)
	_key(KEY_2, true)
	_key(KEY_3)
	engine._process(0.0)
	_check(engine.entity_service.get_counts() == Vector3i(1, 10, 1), "debug spawn and batch keys")

	var before: int = engine.step_count
	engine._process(1.0)
	_check(engine.step_count == before, "pause freezes simulation")

	_key(KEY_N)
	engine._process(0.0)
	_check(engine.step_count == before + 1 and engine.paused, "single step advances once")

	engine._process(0.0)
	_check(engine.step_count == before + 1, "single step is consumed")

	_key(KEY_1, false, true)
	engine._process(0.0)
	_check(engine.entity_service.get_counts().x == 1, "key repeats are ignored")

	var panel: RuntimeConfigPanel = scene.hud.parameters
	panel.show()
	panel.set_draft(engine.config)
	panel.editors["World.initial_total"].get_line_edit().grab_focus()
	_key(KEY_1)
	_key(KEY_R)
	engine._process(0.0)
	_check(engine.entity_service.get_counts() == Vector3i(1, 10, 1), "numeric field focus blocks gameplay shortcuts")

	panel.close()
	_key(KEY_F1)
	_check(engine.debug_service.show_details, "debug overlay toggle")

	engine.config = authored.copy_config()
	engine.reset_simulation()
	var positions: Array[Vector2] = []
	for animal in engine.entity_service.entities:
		positions.append(data.motion_position[animal.row])
	_step(3)
	engine.reset_simulation()
	var repeated: Array[Vector2] = []
	for animal in engine.entity_service.entities:
		repeated.append(data.motion_position[animal.row])
	_check(positions == repeated, "reset reproduces seeded populations")
	_check(engine.step_count == 0 and engine.entity_service.capture_count == 0, "reset clears simulation counters")
	_check(engine.entity_service.get_counts() == authored.get_initial_counts(), "reset preserves configured population")

func _verify_clock() -> void:
	_empty(false)
	engine.config.simulation_hz = 60.0
	engine.config.max_steps_per_frame = 4
	engine.paused = false
	var interval: float = 1.0 / engine.config.simulation_hz
	engine._process(interval * 0.4)
	_check(engine.step_count == 0 and is_equal_approx(engine._accumulator, interval * 0.4), "fractional frame waits for a full step")

	engine._process(interval * 0.6)
	_check(engine.step_count == 1 and is_zero_approx(engine._accumulator), "accumulated full step advances once")

	engine.reset_simulation()
	engine._process(interval * 6.4)
	_check(engine.step_count == 4 and is_equal_approx(engine._accumulator, interval * 0.4), "catch-up is bounded and retains only fractional remainder")

	engine._process(0.0)
	_check(engine.step_count == 4, "discarded backlog is not replayed")

	engine._process(interval * 0.6)
	_check(engine.step_count == 5, "fractional remainder carries into next frame")

	engine.reset_simulation()
	engine._process(interval * 0.4)
	engine.paused = true
	engine._process(100.0)
	_check(engine.step_count == 0 and engine._accumulator == 0.0, "pause discards fractional time and accrues no debt")

	engine.paused = false
	engine._process(interval * 0.6)
	_check(engine.step_count == 0, "resume starts with a fresh accumulator")

	engine._process(interval * 0.4)
	_check(engine.step_count == 1, "resume advances after a new full interval")

	engine.reset_simulation()
	engine.config.simulation_hz = 30.0
	engine.paused = true
	engine.request_single_step()
	engine._process(0.0)
	_check(engine.step_count == 1 and is_equal_approx(engine.simulation_time, 1.0 / 30.0), "single step uses configured interval")

	engine._process(10.0)
	_check(engine.step_count == 1, "single-step request is consumed once")

	engine.paused = false
	engine._process(0.01)
	engine.reset_simulation()
	_check(engine._accumulator == 0.0 and engine.step_count == 0, "reset clears accumulated time")

	var errors_enabled := Engine.print_error_messages
	Engine.print_error_messages = false
	var invalid_results: Array[bool] = []
	for frequency in [0.0, -1.0, NAN, INF, 1.0e-320]:
		engine.config.simulation_hz = frequency
		engine._process(1.0)
		invalid_results.append(engine.step_count == 0 and engine._clock_error_reported)
	engine.config.simulation_hz = 60.0
	engine.config.max_steps_per_frame = 0
	engine._process(1.0)
	invalid_results.append(engine.step_count == 0 and engine._clock_error_reported)
	engine.config.max_steps_per_frame = 4
	for frame_delta in [NAN, INF, -1.0]:
		engine._process(frame_delta)
		invalid_results.append(engine.step_count == 0 and engine._clock_error_reported)
	Engine.print_error_messages = errors_enabled
	for result in invalid_results:
		_check(result, "invalid clock input prevents automatic stepping")
	engine._process(1.0 / 60.0)
	_check(engine.step_count == 1 and not engine._clock_error_reported, "valid configuration resumes automatic stepping")

	_empty(false)
	engine.config.initial_total = 30
	engine.config.sheep_ratio = 24.0
	engine.config.wolf_ratio = 4.0
	engine.config.sheepdog_ratio = 2.0
	engine.reset_simulation()
	for index in range(120):
		engine._process(1.0 / 60.0)
	var expected_steps: int = engine.step_count
	var expected_time: float = engine.simulation_time
	engine.reset_simulation()
	for index in range(60):
		engine._process(1.0 / 120.0)
		engine._process(3.0 / 120.0)
	_check(engine.step_count == expected_steps and is_equal_approx(engine.simulation_time, expected_time) and is_zero_approx(engine._accumulator), "frame grouping preserves step count and simulated time with asynchronous decisions")

	engine.reset_simulation()
	engine._process(interval * 0.4)
	var replacement: SimulationConfig = engine.config.copy_config()
	replacement.initial_total = 1
	replacement.sheep_ratio = 1.0
	replacement.wolf_ratio = 0.0
	replacement.sheepdog_ratio = 0.0
	engine.request_config_apply(replacement)
	engine._process(0.0)
	_check(engine._accumulator == 0.0 and engine.step_count == 0 and engine.entity_service.get_counts().x == 1, "configuration restart clears partial step")

func _verify_ecs_storage() -> void:
	_empty()
	var service: EntityService = engine.entity_service
	service.clear()
	var data := service.data
	var prey := _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(100, 300))
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(900, 300))
	data.memory_target[wolf.row] = prey
	data.dog_protected_sheep[dog.row] = prey
	data.dog_collected_sheep[dog.row] = prey
	var old_uid := prey.uid
	var old_slot := prey.slot
	var agent := data.brain_agent[prey.row]
	var player := data.brain_player[prey.row]
	_check(player == null, "sheep pooling needs no behavior tree")

	data.sheep_panic_strength[prey.row] = 1
	data.sheep_threat_strength[prey.row] = 0.6
	data.sheep_panic_source[prey.row] = Vector2(350, 250)
	data.motion_velocity[prey.row] = Vector2(20, 10)
	data.motion_velocity[dog.row] = Vector2(7, 9)
	data.dog_protection_center[dog.row] = Vector2(800, 250)
	var dog_uid := dog.uid
	engine.debug_service.selected = prey
	_check(service.capture(prey) and not service.capture(prey), "death captures exactly once")
	_check(data.live(data.memory_target[wolf.row]) == null and engine.debug_service.selected == null, "death invalidates target and selection immediately")

	service.remove_expired()
	_check(not prey.enabled and _render_visible(prey) and player == null and agent == null, "disabled life keeps a short corpse presentation")
	_check(data.sheep_panic_strength[prey.row] == 1.0 and data.sheep_threat_strength[prey.row] == 0.6 and data.sheep_panic_source[prey.row] == Vector2(350, 250), "row swap preserves continuous sheep fields")
	_check(data.active_count == 2 and data.retained_count == 3 and not service.entities.has(prey), "corpse is outside the contiguous active prefix")
	_check(dog.row == 0 and dog.uid == dog_uid and data.motion_position[dog.row] == Vector2(900, 300) and data.motion_velocity[dog.row] == Vector2(7, 9) and data.dog_protection_center[dog.row] == Vector2(800, 250), "row swap preserves identity and independent component fields")
	_check(data.brain_agent[dog.row].entity == dog and data.live(data.dog_collected_sheep[dog.row]) == null, "row swap preserves scene association and invalidates dog references")

	for row in range(data.row_to_slot.size()):
		_check(data.slot_to_row[data.row_to_slot[row]] == row, "slot mapping follows row swap")
	var remaining := data.identity_death_remaining[prey.row]
	engine._process(1.0)
	_check(data.identity_death_remaining[prey.row] == remaining, "pause freezes corpse lifetime")

	var extra := _animal(AnimalEntity.Kind.SHEEP, Vector2(700, 400))
	_check(extra.slot != old_slot and _render_visible(prey), "spawning cannot reuse a visible corpse")

	_step(20)
	_check(not _render_visible(prey) and data.retained_count == data.active_count, "expired corpse enters the reusable suffix")

	var allocated := data.row_to_slot.size()
	var replacement := _animal(AnimalEntity.Kind.SHEEP, Vector2(600, 400))
	_check(replacement.slot == old_slot and replacement.uid != old_uid and data.row_to_slot.size() == allocated, "reuse keeps the slot and allocates a new uid without growing storage")
	_check(data.row_of(prey) == -1 and data.live(prey) == null and data.live(data.memory_target[wolf.row]) == null, "old life handle cannot follow a reused slot")
	_check(data.brain_agent[replacement.row] == null and data.brain_player[replacement.row] == null, "reuse preserves sheep presentation without a behavior tree")
	_check(data.sheep_panic_strength[replacement.row] == 0.0 and data.sheep_threat_strength[replacement.row] == 0.0 and data.sheep_panic_source[replacement.row] == Vector2.ZERO and data.motion_velocity[replacement.row] == Vector2.ZERO and data.memory_target[replacement.row] == null, "reuse clears previous life state")
	engine.render_service.sync()
	_check(_render_transform(replacement).origin == Vector2(600, 400) and replacement.enabled, "reuse synchronizes spawn presentation")
	_check(service.capture(extra) and service.capture(replacement), "multiple deaths can be queued in one interaction phase")

	service.remove_expired()
	_check(data.active_count == 2 and service.get_counts() == Vector3i(0, 1, 1), "compaction does not skip consecutive deaths")

	var last_uid := dog.uid
	for index in range(3):
		engine.reset_simulation()
	_check(data.row_to_slot.size() == allocated and service.get_counts() == Vector3i.ZERO, "empty resets retain allocated storage without growth")

	var new_dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(900, 300))
	_check(new_dog.uid > last_uid and data.live(dog) == null, "reset does not recycle uid values")

	service.clear()
	var after_clear := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(900, 300))
	_check(after_clear.uid > new_dog.uid and data.live(new_dog) == null, "clear cannot revive an old handle")

func _verify_debug_panel() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	engine.entity_service.clear()
	var debug: DebugService = engine.debug_service
	var panel: DebugPanel = scene.hud.debug_panel
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300))
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(550, 300))
	data.memory_target[wolf.row] = sheep
	data.memory_target_visible[wolf.row] = int(false)
	data.memory_last_seen_position[wolf.row] = Vector2(500, 320)
	debug.selected = wolf
	debug.show_details = false
	debug.selected_only = true
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_F3
	scene.hud._unhandled_key_input(event)
	_check(panel.visible and not scene.hud.parameters.visible, "F3 opens DebugPanel separately from parameters")

	panel.enabled_toggle.button_pressed = true
	_check(debug.show_details, "panel enables auxiliary visuals immediately")

	panel.scope.select(1)
	panel.scope.item_selected.emit(1)
	_check(not debug.selected_only, "panel supports all-animal scope")

	var rng_state: int = engine.rng.state
	var target_position := data.motion_position[sheep.row]
	var remembered := data.memory_last_seen_position[wolf.row]
	data.wolf_howl_pending[wolf.row] = int(true)
	engine.wolf_system.resolve_interactions(wolf, 0.0)
	_check(debug.howl_events.size() == 1, "settled howl records a visual event")

	var origin: Vector2 = debug.howl_events[0]["position"]
	var radius: float = debug.howl_events[0]["radius"]
	data.motion_position[wolf.row] += Vector2(40, 0)
	var draft: SimulationConfig = engine.config.copy_config()
	draft.wolf.howl_radius += 10.0
	engine.request_config_apply(draft)
	engine._process(0.0)
	_check(debug.howl_events[0]["position"] == origin and debug.howl_events[0]["radius"] == radius, "howl snapshots origin and range at settlement")

	engine._process(1.0)
	_check(debug.howl_events[0]["elapsed"] == 0.0, "pause freezes howl pulse")

	debug.advance_visuals(0.1)
	_check(is_equal_approx(debug.howl_events[0]["elapsed"], 0.1), "visual event advances with simulation delta")

	panel.controls["howl"].button_pressed = false
	_check(debug.howl_events.is_empty(), "disabling howl clears pending presentation")

	panel.controls["howl"].button_pressed = true
	_check(debug.howl_events.is_empty(), "reenabling does not replay old howls")
	_check(engine.rng.state == rng_state and data.motion_position[sheep.row] == target_position and data.memory_last_seen_position[wolf.row] == remembered, "visual controls preserve RNG and hidden target memory")

	panel.close()
	_check(debug.show_details and not panel.visible, "closing panel preserves visual choices")

	event.keycode = KEY_F2
	scene.hud._unhandled_key_input(event)
	_check(scene.hud.parameters.visible and not panel.visible, "F2 keeps panels mutually exclusive")

	event.keycode = KEY_F3
	scene.hud._unhandled_key_input(event)
	_check(panel.visible and not scene.hud.parameters.visible, "opening DebugPanel closes parameters")

	event.keycode = KEY_ESCAPE
	scene.hud._unhandled_key_input(event)
	_check(not panel.visible, "Escape closes DebugPanel")

	engine.reset_simulation()
	_check(debug.show_details and not debug.selected_only and debug.howl_events.is_empty(), "reset keeps visual preferences and clears effects")

	debug.show_details = false
	debug.selected_only = true

func _verify_batch_steering() -> void:
	_empty(false)
	var data: AnimalData = engine.entity_service.data
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(600, 400))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(700, 400))
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(800, 400))
	data.motion_intent[sheep.row] = AnimalData.MotionIntent.SHEEP
	engine.config.sheep.wander_weight = 0.0
	data.sheep_neighbor_count[sheep.row] = 0
	data.sheep_alignment[sheep.row] = Vector2.RIGHT * 10.0
	var expected: Vector2 = Vector2.RIGHT * 10.0 * engine.config.sheep.alignment_weight * minf(1.0, engine.config.sheep.steering_rate / 60.0)
	data.brain_current_behavior[wolf.row] = AnimalEntity.Behavior.STALK
	data.wolf_strategy[wolf.row] = AnimalEntity.Strategy.SIDE
	data.memory_last_seen_velocity[wolf.row] = Vector2.RIGHT
	data.memory_last_seen_position[wolf.row] = Vector2(600, 400)
	engine.animal_system.move_towards(wolf, Vector2(600, 400), 50.0, 1.0 / 60.0)
	_check(data.motion_desired_velocity[wolf.row] == Vector2.ZERO, "point intent defers velocity until steering stage")

	data.brain_current_behavior[dog.row] = AnimalEntity.Behavior.COLLECT
	data.dog_protection_center[dog.row] = Vector2(600, 400)
	data.dog_collected_sheep[dog.row] = sheep
	data.motion_position[sheep.row] = Vector2(700, 400)
	engine.animal_system.move_towards(dog, Vector2(700, 400), 60.0, 1.0 / 60.0)
	var state: int = engine.rng.state
	engine.animal_system.update_steering(1.0 / 60.0)
	_check(data.motion_desired_velocity[sheep.row].is_equal_approx(expected), "batch sheep steering preserves alignment and smoothing without a state")
	_check(data.motion_movement_goal[wolf.row].is_equal_approx(Vector2(600, 400 - engine.config.wolf.strategy_offset)), "batch wolf side strategy offsets last seen position")
	_check(data.motion_movement_goal[dog.row].is_equal_approx(Vector2(700 + engine.config.sheepdog.collect_distance, 400)), "batch dog collect point stays outside sheep relative to flock")
	_check(engine.rng.state == state, "steering does not consume RNG")

	data.brain_current_behavior[wolf.row] = AnimalEntity.Behavior.RETREAT
	data.wolf_nearest_threat[wolf.row] = dog
	engine.animal_system.move_towards(wolf, data.motion_position[wolf.row], 50.0, 1.0 / 60.0)
	engine.animal_system.update_steering(1.0 / 60.0)
	_check(data.motion_desired_velocity[wolf.row].x < 0.0, "batch retreat moves away from actual threat")

	data.motion_intent[wolf.row] = AnimalData.MotionIntent.STOP
	data.motion_desired_velocity[wolf.row] = Vector2.ZERO
	engine.animal_system.update_steering(1.0 / 60.0)
	_check(data.motion_desired_velocity[wolf.row] == Vector2.ZERO, "stop intent cannot reuse previous point velocity")

	data.motion_intent[dog.row] = AnimalData.MotionIntent.POINT
	engine.entity_service.capture(sheep)
	engine.entity_service.remove_expired(1.0)
	_check(data.motion_intent[dog.row] == AnimalData.MotionIntent.POINT, "row compaction preserves motion intent")

	var reused := _animal(AnimalEntity.Kind.SHEEP, Vector2(600, 400))
	_check(data.motion_intent[reused.row] == AnimalData.MotionIntent.STOP, "reused row clears previous motion intent")

func _verify_pressure_sampling() -> void:
	_empty()
	var data: AnimalData = engine.entity_service.data
	var grid: GridService = engine.grid_service
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(401, 307))
	var neighbor := _animal(AnimalEntity.Kind.SHEEP, Vector2(402, 306))
	_animal(AnimalEntity.Kind.SHEEP, Vector2(403, 308))
	_animal(AnimalEntity.Kind.SHEEP, Vector2(405, 310))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(300, 300))
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(401, 250))
	engine.config.sheep.wolf_pressure_distance = 100.0
	grid.rebuild()
	engine.wolf_system.accumulate_sheep_pressure()
	engine.dog_system.accumulate_sheep_pressure()
	_check(data.sheep_threat_strength[sheep.row] == 0 and data.sheep_threat_direction[sheep.row] == Vector2.ZERO, "interpolation does not create a wolf threat outside exact radius")

	data.motion_position[wolf.row] = Vector2(302, 307)
	grid.rebuild()
	engine.wolf_system.accumulate_sheep_pressure()
	_check(data.sheep_threat_strength[sheep.row] > 0 and data.sheep_threat_direction[sheep.row].x > 0.0, "sampled pressure points away inside exact radius")

	var before := data.sheep_threat_direction[sheep.row]
	data.motion_position[sheep.row] += Vector2(1, 0)
	grid.rebuild()
	engine.wolf_system.accumulate_sheep_pressure()
	_check(data.sheep_threat_strength[sheep.row] == 0 and not data.sheep_threat_direction[sheep.row].is_equal_approx(before), "within-cell motion reaches zero pressure at exact radius")

	data.motion_position[sheep.row].x += 0.01
	grid.rebuild()
	engine.wolf_system.accumulate_sheep_pressure()
	_check(data.sheep_threat_strength[sheep.row] == 0, "subpixel motion beyond true wolf radius clears threat")

	data.motion_position[dog.row] = Vector2(401, 100)
	grid.rebuild()
	engine.dog_system.accumulate_sheep_pressure()
	_check(data.sheep_dog_pressure[sheep.row] == Vector2.ZERO, "dog field is zero outside actual radius")
	_check(grid.pressure_sample_count == 4, "one dense sheep cell shares four pressure nodes")

	engine.entity_service.capture(wolf)
	engine.entity_service.remove_expired(1.0)
	grid.rebuild()
	engine.wolf_system.accumulate_sheep_pressure()
	_check(data.sheep_threat_strength[sheep.row] == 0 and data.sheep_threat_direction[sheep.row] == Vector2.ZERO, "dead pressure source does not survive row compaction")

	engine.entity_service.capture(neighbor)
	engine.entity_service.remove_expired(1.0)
	data.motion_position[dog.row] = Vector2(401, 250)
	grid.rebuild()
	engine.dog_system.accumulate_sheep_pressure()
	var offset := data.motion_position[sheep.row] - data.motion_position[dog.row]
	var exact: Vector2 = offset.normalized() * (1.0 - offset.length() / engine.config.sheep.herding_distance)
	_check(grid.pressure_sample_count == 0 and data.sheep_dog_pressure[sheep.row].is_equal_approx(exact), "sparse cell avoids field setup and preserves exact pressure after density transition")

func _verify_shared_protection() -> void:
	_empty()
	var data: AnimalData = engine.entity_service.data
	var grid: GridService = engine.grid_service
	var anchor := _animal(AnimalEntity.Kind.SHEEP, Vector2(601, 301))
	var neighbor := _animal(AnimalEntity.Kind.SHEEP, Vector2(620, 320))
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(600, 300))
	var other := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(600, 350))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(700, 310))
	data.dog_protected_sheep[dog.row] = anchor
	data.dog_protected_sheep[other.row] = neighbor
	data.dog_assignment_remaining[dog.row] = 10.0
	data.dog_assignment_remaining[other.row] = 10.0
	data.motion_facing[dog.row] = Vector2.RIGHT
	data.motion_facing[other.row] = Vector2.LEFT
	grid.rebuild()
	engine.dog_system.perceive(dog, 1.0 / 60.0)
	engine.dog_system.perceive(other, 1.0 / 60.0)
	_check(engine.dog_system.shared_group_count == 1 and engine.dog_system.shared_group_hits > 0, "same-cell anchors reuse one protection group")
	_check(data.dog_protection_center[dog.row].is_equal_approx(Vector2(610.5, 310.5)) and data.dog_protection_center[dog.row] == data.dog_protection_center[other.row], "shared patrol center uses actual sheep positions rather than grid center")
	_check(data.dog_wolf_candidates[dog.row].has(wolf) and not data.dog_wolf_candidates[other.row].has(wolf), "shared wolf candidates do not share individual vision")

	data.motion_position[neighbor.row] += Vector2(2, 0)
	grid.rebuild()
	engine.dog_system.perceive(dog, 1.0 / 60.0)
	_check(data.dog_protection_center[dog.row].is_equal_approx(Vector2(611.5, 310.5)), "within-cell sheep movement updates shared patrol center")

	data.motion_position[neighbor.row] = Vector2(640, 320)
	grid.rebuild()
	engine.dog_system.perceive(dog, 1.0 / 60.0)
	engine.dog_system.perceive(other, 1.0 / 60.0)
	_check(engine.dog_system.shared_group_count == 2, "cross-cell anchors build separate protection groups")

	data.motion_position[dog.row] = Vector2(1100, 600)
	data.dog_returning[dog.row] = 1
	grid.rebuild()
	engine.dog_system.perceive(dog, 1.0 / 60.0)
	_check(engine.dog_system.shared_group_count == 1 and engine.dog_system.shared_candidate_groups == 0, "returning dog reads flock center without preparing target candidates")

	engine.entity_service.clear()
	_check(grid.members.is_empty(), "reset drops spatial data used by shared protection")

func _run() -> void:
	verification_directory = "res://output/verification/" + Time.get_datetime_string_from_system().replace(":", "-") + "_" + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(verification_directory)
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	authored = scene.simulation_config
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	await process_frame
	_check(not engine.debug_service.show_details and not scene.hud.debug_panel.visible and engine.debug_service.selected_only, "default presentation keeps overlays off with selected-only scope")

	_verify_resources_and_vision()
	_verify_population_config()
	_verify_sheep()
	_verify_continuous_sheep()
	_verify_grid_and_pressure()
	_verify_batch_steering()
	_verify_pressure_sampling()
	_verify_shared_protection()
	_verify_wolves()
	_verify_dogs()
	_verify_behavior_edges()
	_verify_runtime_config()
	_verify_controls()
	_verify_clock()
	_verify_ecs_storage()
	_verify_multimesh()
	_verify_debug_panel()
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	authored = null
	scene = null
	engine = null
	print("SIMULATION_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _render_index(animal: AnimalEntity) -> int:
	var data: AnimalData = engine.entity_service.data
	var index := 0
	for row in range(animal.row):
		if data.identity_kind[row] == data.identity_kind[animal.row]:
			index += 1
	return index

func _render_visible(animal: AnimalEntity) -> bool:
	var data: AnimalData = engine.entity_service.data
	return animal.row >= 0 and animal.row < data.retained_count and data.handles[animal.row] == animal

func _render_transform(animal: AnimalEntity) -> Transform2D:
	var data: AnimalData = engine.entity_service.data
	var buffer: PackedFloat32Array = engine.render_service.buffers[data.identity_kind[animal.row]]
	var index := _render_index(animal) * 12
	return Transform2D(Vector2(buffer[index], buffer[index + 4]), Vector2(buffer[index + 1], buffer[index + 5]), Vector2(buffer[index + 3], buffer[index + 7]))

func _verify_multimesh() -> void:
	_empty(false)
	var service: EntityService = engine.entity_service
	var data: AnimalData = service.data
	var render: RenderService = engine.render_service
	_check(render.instances.size() == 3, "three shared species renderers exist")
	_check(render.instances[0].get_parent() == scene.get_node("World/Animals") and engine.debug_service.z_index > render.instances[0].z_index, "render visibility and debug layer stay attached to the world")
	for instance in render.instances:
		_check(instance.multimesh.visible_instance_count == 0, "reset hides all previous instances")
	var arrays := render.instances[1].multimesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	_check(vertices[0].y < 0 and uvs[0] == Vector2.ZERO and vertices[2].y > 0 and uvs[2] == Vector2.ONE, "mesh UVs preserve Sprite top-down orientation")
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(222, 333))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300))
	var other := _animal(AnimalEntity.Kind.WOLF, Vector2(500, 300))
	var state: int = engine.rng.state
	engine._process(0.0)
	_check(not render.dirty and _render_transform(sheep).origin.is_equal_approx(Vector2(222, 333)), "paused structural edits flush render data")
	_check(engine.rng.state == state and data.brain_agent[sheep.row] == null, "rendering consumes no RNG and sheep creates no agent")
	_check(data.brain_player[wolf.row] != data.brain_player[other.row] and data.brain_player[wolf.row].get_blackboard() != data.brain_player[other.row].get_blackboard(), "wolves own independent players and blackboards")
	data.brain_player[wolf.row].get_blackboard().set_var("old_life", 123)
	var player := data.brain_player[wolf.row]
	var old_uid := wolf.uid
	engine.reset_simulation()
	var replacement := _animal(AnimalEntity.Kind.WOLF, Vector2(300, 300))
	_check(data.brain_player[replacement.row] == player and replacement.uid != old_uid and not player.get_blackboard().has_var("old_life") and data.brain_agent[replacement.row].entity == replacement, "agent reuse clears blackboard and rebinds the new life")
	var flock := service.spawn(AnimalEntity.Kind.SHEEP, 12, Vector2(600, 400))
	render.sync()
	var capacity := render.instances[0].multimesh.instance_count
	_check(render.instances[0].multimesh.visible_instance_count == 12, "buffer growth displays every spawned sheep")
	service.capture(flock[0])
	service.remove_expired()
	render.sync()
	_check(render.instances[0].multimesh.visible_instance_count == 12, "corpse remains visible outside active prefix")
	var index := _render_index(flock[0]) * 12 + 8
	var buffer := render.buffers[0]
	_check(Color(buffer[index], buffer[index + 1], buffer[index + 2], buffer[index + 3]).is_equal_approx(Color("#7b8794")), "corpse uses the existing dead color")
	service.remove_expired(10.0)
	render.sync()
	_check(render.instances[0].multimesh.visible_instance_count == 11 and render.instances[0].multimesh.instance_count == capacity, "expiration hides suffix without shrinking capacity")
	service.clear()
	engine._process(0.0)
	for instance in render.instances:
		_check(instance.multimesh.visible_instance_count == 0, "clear removes every visible instance")
