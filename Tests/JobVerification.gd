extends SceneTree

class ProbeJob extends Job:
	var delay_ms: int = 0
	var applied: Array[int]
	var main_thread: bool = false
	var worker_thread: bool = false
	var value: int = 0

	func execute() -> void:
		OS.delay_msec(delay_ms)
		worker_thread = not Thread.is_main_thread()
		value = batch

	func apply_result() -> void:
		main_thread = Thread.is_main_thread()
		applied.append(value)

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node
var authored: SimulationConfig

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _queues() -> void:
	var service := JobService.new()
	root.add_child(service)
	var applied: Array[int] = []
	var first := ProbeJob.new()
	first.stage = &"Probe"
	first.batch = 0
	first.delay_ms = 40
	first.applied = applied
	_check(not service.add_job(first), "stopped service rejects jobs")

	service.startup()

	service.finish_stage()
	_check(service.pending.is_empty() and service.working.is_empty() and service.completed.is_empty(), "empty stage completes")

	var second := ProbeJob.new()
	second.stage = &"Probe"
	second.batch = 1
	second.applied = applied
	_check(service.add_job(first) and service.add_job(second), "jobs enter pending")
	_check(not service.add_job(first), "duplicate pending job rejected")

	var other := ProbeJob.new()
	other.stage = &"Other"
	_check(not service.add_job(other), "different stage cannot enter frozen stage")

	service.dispatch_pending()
	_check(service.pending.is_empty() and service.working.size() == 2, "dispatch moves pending to working")

	while not WorkerThreadPool.is_task_completed(second.task_id):
		OS.delay_msec(1)
	service.collect_completed()
	_check(second.state == Job.State.COMPLETED and applied.is_empty(), "completed result is held until barrier")

	service.finish_stage()
	_check(applied == [0, 1], "out of order completion applies in batch order")
	_check(first.main_thread and second.main_thread and first.worker_thread and second.worker_thread, "execution uses workers and application uses main thread")
	_check(first.task_id == -1 and second.task_id == -1, "task handles reclaimed once")

	service.finish_stage()
	_check(applied.size() == 2, "repeated finish does not apply twice")
	_check(service.add_job(first), "applied job can be reused")

	service.dispatch_pending()
	_check(service.add_job(second), "another job can remain pending during shutdown")

	service.shutdown()
	_check(first.state == Job.State.DISCARDED and second.state == Job.State.DISCARDED and applied.size() == 2, "shutdown waits working and discards pending results")
	_check(service.working.is_empty() and service.completed.is_empty() and service.pending.is_empty(), "shutdown clears queues")

	service.startup()
	_check(service.add_job(first), "service can restart")

	service.reset()
	_check(service.started and first.state == Job.State.DISCARDED, "reset drains while retaining started state")

	service.queue_free()

func _setup(total: int, parallel: bool, detailed: bool = false) -> void:
	engine.job_service.drain()
	engine.entity_service.clear()
	engine.config = authored.copy_config()
	engine.config.initial_total = total
	engine.config.sheep_ratio = 110.0
	engine.config.wolf_ratio = 17.0
	engine.config.sheepdog_ratio = 10.0
	engine.config.death_duration = 0.04
	engine.job_service.parallel_enabled = parallel
	engine.job_service.minimum_parallel_items = 1
	for stage in engine.job_service.parallel_stages:
		engine.job_service.parallel_stages[stage] = true
	engine.profile_service.set_performance_stats_enabled(true, detailed)
	engine.reset_simulation()
	engine.paused = true

func _value(value: Variant) -> Variant:
	if value is AnimalEntity:
		var row: int = engine.entity_service.data.row_of(value)
		return engine.entity_service.data.identity_entity_id[row] if row >= 0 else -1
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_value(item))
		return result
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		return value.duplicate()
	return value

func _state() -> Dictionary:
	var data: AnimalData = engine.entity_service.data
	var result := {"rng": engine.rng.state, "active": data.active_count, "retained": data.retained_count,
		"captures": engine.entity_service.capture_count, "time": engine.simulation_time}
	for property in data.get_property_list():
		var name: String = property.name
		if name in ["identity_animal_id", "settings", "handles", "brain_instance"]:
			continue
		if name.begins_with("identity_") or name.begins_with("motion_") or name.begins_with("memory_") or name.begins_with("sheep_") or name.begins_with("wolf_") or name.begins_with("dog_") or name == "brain_current_behavior":
			result[name] = _value(data.get(name))

	var grid: GridService = engine.grid_service
	for name in ["cell_counts", "cell_offsets", "members", "flock_counts", "flock_position_sums", "alignment_counts", "alignment_velocity_sums", "pressure_nodes", "wolf_pressure", "dog_pressure"]:
		result[name] = grid.get(name).duplicate()
	return result

func _commands(step: int) -> void:
	if step == 12 and not engine.entity_service.sheep_rows.is_empty():
		engine.entity_service.capture(engine.entity_service.data.handles[engine.entity_service.sheep_rows[0]])
	if step == 20:
		engine.request_spawn(AnimalEntity.Kind.SHEEP, 3)
		engine.request_spawn(AnimalEntity.Kind.WOLF, 1)
		engine.request_spawn(AnimalEntity.Kind.SHEEPDOG, 1)
		engine._process(0.0)
	if step == 30:
		var settings: SimulationConfig = engine.config.copy_config()
		settings.sheep.cohesion_weight *= 0.75
		engine.request_config_apply(settings)
		engine._process(0.0)
	if step == 40:
		var settings: SimulationConfig = engine.config.copy_config()
		settings.random_seed += 1
		engine.request_config_apply(settings)
		engine._process(0.0)
	if step == 50:
		engine.request_single_step()
		engine._process(0.0)

func _equivalence(total: int) -> void:
	_setup(total, false)
	var states: Array[Dictionary] = []
	for step in range(65):
		_commands(step)
		engine.simulate_step(1.0 / 60.0)
		_wait_decisions()
		states.append(_state())

	for workers in [2, 4, 8]:
		_setup(total, true, workers == 8)
		engine.job_service.max_workers = workers
		for step in range(65):
			_commands(step)
			engine.simulate_step(1.0 / 60.0)
			_wait_decisions()
			var observed := _state()
			_check(observed == states[step], "exact serial/parallel state total=%d workers=%d step=%d" % [total, workers, step])

			if observed != states[step]:
				for key in observed:
					if observed[key] != states[step][key]:
						print("FIRST_DIFFERENCE ", key, " expected=", states[step][key], " actual=", observed[key])
				return
		_check(engine.job_service.pending.is_empty() and engine.job_service.working.is_empty() and engine.job_service.completed.is_empty(), "simulation stage queues drained")

func _wait_decisions() -> void:
	while not engine.job_service.async_jobs.is_empty():
		for job: Job in engine.job_service.async_jobs.values():
			while job.state == Job.State.WORKING and not WorkerThreadPool.is_task_completed(job.task_id):
				OS.delay_msec(1)
		engine.animal_service.apply_completed()

func _dog_snapshot() -> void:
	_setup(0, true)
	var entities: EntityService = engine.entity_service
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(300, 300))[0]
	var dogs := entities.spawn(AnimalEntity.Kind.SHEEPDOG, 2, Vector2(300, 300))
	engine.grid_service.rebuild()
	engine.dog_system.begin_spatial_step()
	engine.dog_system.perceive_batch(1.0 / 60.0)
	_check(entities.data.dog_protected_sheep[dogs[0].row] == sheep and entities.data.dog_protected_sheep[dogs[1].row] == sheep, "simultaneous anchor choice allows shared protection")

	var other := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(500, 300))[0]
	engine.config.sheepdog.local_flock_radius = 80.0
	engine.config.sheepdog.coverage_weight = 10.0
	engine.config.sheepdog.reassignment_improvement = 0.0
	entities.data.dog_protected_sheep[dogs[0].row] = null
	entities.data.dog_protected_sheep[dogs[1].row] = sheep
	entities.data.dog_assignment_remaining[dogs[1].row] = 100.0
	engine.grid_service.rebuild()
	engine.dog_system.begin_spatial_step()
	engine.dog_system.perceive_batch(1.0 / 60.0)
	_check(entities.data.dog_protected_sheep[dogs[0].row] == other, "old anchor coverage penalty remains effective")

func _grid_oracle() -> void:
	_setup(0, true)
	engine.config.arena_size = Vector2(360, 240)
	engine.config.sheep.flock_radius = 65.0
	engine.config.sheep.alignment_radius = 35.0
	var entities: EntityService = engine.entity_service
	for point in [Vector2(12, 94), Vector2(31, 94), Vector2(300, 180), Vector2(347, 182)]:
		for index in range(4):
			var animal := entities.spawn(AnimalEntity.Kind.SHEEP, 1, point)[0]
			entities.data.motion_velocity[animal.row] = Vector2(index, -index)

	var grid: GridService = engine.grid_service
	grid.rebuild()
	var nodes := PackedInt32Array()
	for cell in range(grid.width * grid.height):
		var sheep_count := grid.cell_counts[cell * 3]
		if sheep_count == 0:
			_check(grid.flock_counts[cell] == 0 and grid.alignment_counts[cell] == 0, "empty grid has no aggregate")

			continue

		var coordinate := Vector2i(cell % grid.width, cell / grid.width)
		var count := 0
		var aligned := 0
		var sum := Vector2.ZERO
		var velocity := Vector2.ZERO
		for neighbor in range(grid.width * grid.height):
			var other := Vector2i(neighbor % grid.width, neighbor / grid.width)
			var squared := Vector2(coordinate - other).length_squared() * grid.cell_size * grid.cell_size
			if squared <= engine.config.sheep.flock_radius * engine.config.sheep.flock_radius:
				count += grid.cell_counts[neighbor * 3]
				sum += grid.sheep_position_sums[neighbor]
			if squared <= engine.config.sheep.alignment_radius * engine.config.sheep.alignment_radius:
				aligned += grid.cell_counts[neighbor * 3]
				velocity += grid.sheep_velocity_sums[neighbor]
		_check(grid.flock_counts[cell] == count and grid.flock_position_sums[cell] == sum, "flock aggregate matches brute force")
		_check(grid.alignment_counts[cell] == aligned and grid.alignment_velocity_sums[cell] == velocity, "alignment aggregate matches brute force")

		if sheep_count >= GridService.PRESSURE_SHARED_MIN_SHEEP:
			var base := coordinate.y * (grid.width + 1) + coordinate.x
			for node in [base, base + 1, base + grid.width + 1, base + grid.width + 2]:
				if not nodes.has(node):
					nodes.append(node)
	_check(grid.pressure_nodes == nodes, "pressure nodes merge deterministically without duplicates")

func _perception_reference() -> void:
	_setup(137, false)
	engine.grid_service.rebuild()
	for row in engine.entity_service.sheep_rows:
		engine.sheep_system.perceive(engine.entity_service.data.handles[row], 1.0 / 60.0)
	for row in engine.entity_service.wolf_rows:
		engine.wolf_system.perceive(engine.entity_service.data.handles[row], 1.0 / 60.0)
	var reference := _state()
	_setup(137, true)
	engine.grid_service.rebuild()
	engine.sheep_system.perceive_batch(1.0 / 60.0)
	engine.wolf_system.perceive_batch(1.0 / 60.0)
	_check(_state() == reference, "sheep and wolf batch perception preserves original sequential behavior and RNG")

func _async_contracts() -> void:
	_setup(0, true)
	engine.config.arena_size = Vector2(1280, 720)
	var entities: EntityService = engine.entity_service
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(300, 300))[0]
	var data := entities.data
	data.motion_intent[sheep.row] = AnimalData.MotionIntent.STOP
	data.motion_desired_velocity[sheep.row] = Vector2.RIGHT * 60.0
	data.motion_speed_limit[sheep.row] = 60.0
	var applied_values: Array[int] = []
	var slow := ProbeJob.new()
	slow.stage = &"Sheep"
	slow.delay_ms = 250
	slow.applied = applied_values
	engine.job_service.submit_async(slow)
	for index in range(10):
		engine.simulate_step(1.0 / 60.0)
	_check(data.motion_position[sheep.row].is_equal_approx(Vector2(310, 300)), "movement advances while sheep work is outstanding")
	_check(engine.animal_service.requested[0] == 0 and engine.job_service.async_jobs.size() == 1, "busy species does not queue catch-up work")
	while not WorkerThreadPool.is_task_completed(slow.task_id):
		OS.delay_msec(1)
	engine.paused = true
	engine._process(1.0)
	_check(applied_values.is_empty(), "pause holds completed results")
	engine.request_single_step()
	engine._process(0.0)
	_check(applied_values == [0], "single step commits completed work exactly once")

	_setup(0, true)
	engine.config.arena_size = Vector2(1280, 720)
	entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(300, 300))
	entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(900, 300))
	entities.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(600, 500))
	for rates in [Vector3i(24, 12, 12), Vector3i(17, 11, 7)]:
		engine.job_service.drain()
		engine.animal_service.reset()
		engine.config.sheep_update_hz = rates.x
		engine.config.wolf_update_hz = rates.y
		engine.config.sheepdog_update_hz = rates.z
		for index in range(600):
			engine.animal_service.schedule_updates(1.0 / 60.0)
			_wait_decisions()
		for kind in range(3):
			_check(engine.animal_service.requested[kind] == rates[kind] * 10, "independent and fractional frequency counts kind=%d rate=%d" % [kind, rates[kind]])

	_setup(0, true)
	engine.config.arena_size = Vector2(1280, 720)
	sheep = entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(300, 300))[0]
	var survivor := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(310, 300))[0]
	var snapshot: AnimalSnapshot = engine.animal_system.decision_snapshot()
	var captured_grid := GridService.build_snapshot(snapshot)
	var output := SheepPerceptionJob.new()
	output.rows = snapshot.sheep
	output.snapshot = snapshot
	output.grid = captured_grid
	SheepSystem.calculate_snapshot(output)
	entities.capture(sheep)
	entities.remove_expired(1.0)
	data.motion_desired_velocity[survivor.row] = Vector2.INF
	engine.sheep_system.apply_decision(output)
	_check(data.motion_desired_velocity[survivor.row].is_finite(), "snapshot UID mapping follows a row swap")
	var replacement := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(700, 500))[0]
	data.motion_desired_velocity[replacement.row] = Vector2(123, 45)
	engine.sheep_system.apply_decision(output)
	_check(data.motion_desired_velocity[replacement.row] == Vector2(123, 45), "old result cannot write into a reused entity life")
	engine.sheep_system.receive_howl(survivor, Vector2(100, 100))
	data.motion_desired_velocity[survivor.row] = Vector2(12, 34)
	engine.sheep_system.apply_decision(output)
	_check(data.motion_desired_velocity[survivor.row] == Vector2(12, 34) and data.sheep_panic_strength[survivor.row] == 1.0, "old sheep result cannot overwrite a newer howl")

	data.motion_intent[replacement.row] = AnimalData.MotionIntent.POINT
	data.motion_position[replacement.row] = Vector2(700, 500)
	data.motion_movement_goal[replacement.row] = Vector2(701, 500)
	data.motion_speed_limit[replacement.row] = 600.0
	data.motion_separation[replacement.row] = Vector2.ZERO
	for index in range(60):
		entities.update_movement(1.0 / 60.0)
	_check(data.motion_position[replacement.row].is_equal_approx(Vector2(701, 500)), "reused point intent stops at its destination")

func _packed_batches() -> void:
	_setup(0, true)
	var entities: EntityService = engine.entity_service
	var data := entities.data
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 3, Vector2(300, 300))
	var wolves := entities.spawn(AnimalEntity.Kind.WOLF, 2, Vector2(450, 300))
	var dogs := entities.spawn(AnimalEntity.Kind.SHEEPDOG, 3, Vector2(300, 300))
	data.motion_position[sheep[2].row] = Vector2(450, 300)
	for dog in dogs:
		data.motion_facing[dog.row] = Vector2.RIGHT
		data.dog_protected_sheep[dog.row] = sheep[0]
		data.dog_protection_center[dog.row] = Vector2(300, 300)
	engine.grid_service.rebuild()
	var common: AnimalSystem = engine.animal_system
	var sheep_job := SheepPerceptionJob.new()
	common.prepare_job(sheep_job, 1.0 / 60.0)
	sheep_job.rows = PackedInt32Array([sheep[2].row, sheep[0].row])
	engine.sheep_system.calculate_batch(sheep_job)
	engine.sheep_system.apply_batch(sheep_job)
	_check(data.sheep_local_flock_center[sheep[2].row] == sheep_job.centers[0] and data.sheep_local_flock_center[sheep[0].row] == sheep_job.centers[1], "packed sheep submission follows noncontiguous input order")
	sheep_job.rows = PackedInt32Array([sheep[1].row])
	data.memory_perception_ready[sheep[1].row] = 1
	data.memory_perception_remaining[sheep[1].row] = 1.0
	data.motion_separation[sheep[1].row] = Vector2(12, 34)
	engine.sheep_system.calculate_batch(sheep_job)
	_check(sheep_job.centers.size() == 1 and sheep_job.refresh_flags == PackedByteArray([0]) and sheep_job.separations[0] == Vector2(12, 34), "reused sheep batch shrinks and keeps unrefreshed separation")
	sheep_job.rows.clear()
	engine.sheep_system.calculate_batch(sheep_job)
	_check(sheep_job.centers.is_empty() and sheep_job.nearby_offsets == PackedInt32Array([0]) and sheep_job.nearby_members.is_empty(), "empty reused sheep batch clears member ranges")

	var wolf_job := WolfPerceptionJob.new()
	common.prepare_job(wolf_job, 1.0 / 60.0)
	wolf_job.dogs = entities.dog_rows
	wolf_job.rows = entities.wolf_rows.duplicate()
	data.memory_target[wolves[1].row] = sheep[0]
	data.motion_facing[wolves[1].row] = Vector2.LEFT
	engine.wolf_system.calculate_batch(wolf_job)
	_check(wolf_job.visible_flags[1] == 1, "packed observation records visible target")
	wolf_job.rows = PackedInt32Array([wolves[1].row])
	data.memory_target[wolves[1].row] = null
	engine.wolf_system.calculate_batch(wolf_job)
	_check(wolf_job.threat_rows.size() == 1 and wolf_job.visible_flags[0] == 0 and wolf_job.unseen_elapsed[0] == 0.0 and wolf_job.last_positions[0] == Vector2.ZERO, "reused wolf batch clears previous observation")
	wolf_job.rows.clear()
	engine.wolf_system.calculate_batch(wolf_job)
	_check(wolf_job.prey_rows.is_empty() and wolf_job.nearby_offsets == PackedInt32Array([0]) and wolf_job.nearby_members.is_empty(), "empty reused wolf batch clears member ranges")

	var dog_job := DogPerceptionJob.new()
	common.prepare_job(dog_job, 1.0 / 60.0)
	dog_job.config = engine.config.copy_config()
	dog_job.config.sheepdog.local_flock_radius = 80.0
	dog_job.groups.resize(data.active_count)
	for dog in dogs:
		var group := DogPerceptionJob.Group.new()
		group.wolves = entities.wolf_rows
		group.sheep = entities.sheep_rows
		dog_job.groups[dog.row] = group
	dog_job.rows = PackedInt32Array([dogs[2].row, dogs[0].row])
	engine.dog_system.calculate_batch(dog_job)
	engine.dog_system.apply_batch(dog_job)
	_check(dog_job.wolf_offsets == PackedInt32Array([0, 2, 4]) and dog_job.stray_offsets == PackedInt32Array([0, 1, 2]), "packed dog candidates preserve per-result ranges")
	_check(data.dog_wolf_candidates[dogs[2].row] == [wolves[0], wolves[1]] and data.dog_stray_candidates[dogs[0].row] == [sheep[2]], "packed dog submission maps candidates back to input animals")
	dog_job.rows = PackedInt32Array([dogs[1].row])
	dog_job.groups.clear()
	engine.dog_system.calculate_batch(dog_job)
	_check(dog_job.wolf_offsets == PackedInt32Array([0, 0]) and dog_job.stray_offsets == PackedInt32Array([0, 0]) and dog_job.wolves.is_empty() and dog_job.strays.is_empty(), "reused dog batch drops previous candidates")
	dog_job.rows.clear()
	engine.dog_system.calculate_batch(dog_job)
	_check(dog_job.separations.is_empty() and dog_job.wolf_offsets == PackedInt32Array([0]) and dog_job.stray_offsets == PackedInt32Array([0]), "empty reused dog batch retains terminal offsets")

	var anchor_job := DogAnchorJob.new()
	common.prepare_job(anchor_job, 1.0 / 60.0)
	anchor_job.config = dog_job.config
	anchor_job.sheep = entities.sheep_rows
	anchor_job.anchors.resize(data.active_count)
	anchor_job.anchors.fill(-1)
	anchor_job.coverage.resize(data.active_count)
	anchor_job.rows = entities.dog_rows.duplicate()
	engine.dog_system.calculate_anchors(anchor_job)
	anchor_job.rows = PackedInt32Array([dogs[1].row])
	engine.dog_system.calculate_anchors(anchor_job)
	_check(anchor_job.anchor_rows.size() == 1 and anchor_job.anchor_rows[0] == sheep[0].row, "reused anchor batch shrinks without stale rows")
	anchor_job.rows.clear()
	engine.dog_system.calculate_anchors(anchor_job)
	_check(anchor_job.anchor_rows.is_empty(), "empty reused anchor batch clears output")

	var grid_job := GridAggregateJob.new()
	grid_job.grid = GridSnapshot.new()
	grid_job.grid.width = 2
	grid_job.grid.height = 2
	grid_job.grid.counts = PackedInt32Array([1, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0])
	grid_job.grid.position_sums = PackedVector2Array([Vector2.ONE, Vector2.ZERO, Vector2.ZERO, Vector2(5, 5)])
	grid_job.grid.velocity_sums = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	grid_job.flock_offsets = PackedInt32Array([0, 0])
	grid_job.alignment_offsets = PackedInt32Array([0, 0])
	grid_job.rows = PackedInt32Array([3, 0])
	grid_job.execute()
	_check(grid_job.flock_counts == PackedInt32Array([5, 1]) and not grid_job.nodes.is_empty(), "packed grid aggregates follow input cell order")
	grid_job.rows = PackedInt32Array([0])
	grid_job.execute()
	_check(grid_job.flock_counts == PackedInt32Array([1]) and grid_job.nodes.is_empty(), "reused grid batch shrinks and clears pressure nodes")
	grid_job.rows.clear()
	grid_job.execute()
	_check(grid_job.flock_sums.is_empty() and grid_job.alignment_counts.is_empty(), "empty reused grid batch clears aggregates")

func _run() -> void:
	_queues()
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	scene.simulation_config = scene.simulation_config.copy_config()
	scene.simulation_config.initial_total = 137
	scene.simulation_config.arena_size = Vector2(1280, 720)
	scene.simulation_config.simulation_hz = 60.0
	scene.simulation_config.sheep_update_hz = 24
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	if engine.sheep_system == null or engine.wolf_system == null or engine.dog_system == null:
		push_error("Simulation systems failed to initialize")
		quit(1)
		return
	engine.set_process(false)
	authored = engine.config.copy_config()
	for total in [0, 1, 137]:
		_equivalence(total)

	_async_contracts()
	_dog_snapshot()
	_grid_oracle()
	_perception_reference()
	_packed_batches()
	engine.stop_simulation()
	_check(not engine.job_service.started, "job service participates in engine shutdown")

	scene.queue_free()
	print("JOB_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
