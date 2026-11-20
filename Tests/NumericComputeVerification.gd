extends SceneTree

const ReferenceSimulation = preload("res://Tests/ReferenceSimulation.gd")

class HeldSheep extends SheepComputeJob:
	var entered: Semaphore = Semaphore.new()
	var gate: Semaphore = Semaphore.new()

	func _execute_gpu() -> PackedByteArray:
		entered.post()
		gate.wait()
		return super._execute_gpu()

class FailedNumeric extends ComputeShaderService:
	func _supports_device() -> bool:
		return true

	func _initialize_device() -> void:
		pass

class FailedNumericJob extends NumericComputeJob:
	func _execute_gpu() -> PackedByteArray:
		error = "Injected numeric failure"
		return PackedByteArray()

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _receive(job: NumericComputeJob) -> void:
	var compute: ComputeShaderService = engine.compute_service
	_check(compute.submit_numeric(job), "numeric job accepted")
	compute.wait_for(job)
	_check(job.error.is_empty() and job.metrics.gpu_ms >= 0.0, "GPU pass completes with timestamps")

func _movement() -> void:
	var entities: EntityService = engine.entity_service
	var data: AnimalData = engine.data_service.animals
	var empty: NumericComputeJob = NumericComputeJob.new()
	empty.capture(data, engine.config, 1.0 / 30.0)
	_receive(empty)
	_check(empty.commit(data), "empty GPU pass retains inactive columns")
	for amount in [1, 15, 130]:
		engine.reset_simulation()
		engine.paused = true
		entities.spawn(AnimalEntity.Kind.SHEEP, amount)
		entities.spawn(AnimalEntity.Kind.WOLF, 3)
		entities.spawn(AnimalEntity.Kind.SHEEPDOG, 2)
		for row in range(data.index.active_count):
			data.motion.intent[row] = row % 3
			data.motion.position[row] = Vector2(12, 94) if row % 4 == 0 else Vector2(1268, 662)
			data.motion.velocity[row] = Vector2(-130, 40)
			data.motion.desired_velocity[row] = Vector2(80, -200)
			data.motion.speed_limit[row] = 0.0 if row % 7 == 0 else 100.0
			data.motion.movement_goal[row] = data.motion.position[row] if row % 5 == 0 else Vector2(600, 300)
			data.motion.separation[row] = Vector2(-0.2, 0.3)
		for interval in [0.0, 1.0 / 30.0, 0.2]:
			var job: NumericComputeJob = NumericComputeJob.new()
			job.capture(data, engine.config, interval)
			ReferenceSimulation.update_movement(data, interval)
			var expected := [data.motion.position.duplicate(), data.motion.velocity.duplicate(), data.motion.facing.duplicate(), data.motion.desired_velocity.duplicate()]
			_receive(job)
			for column in range(4):
				for row in range(data.index.active_count):
					_check(job.output[column][row].distance_to(expected[column][row]) <= 0.015, "movement matches CPU column %d row %d" % [column, row])
			_check(job.commit(data), "matching step commits movement columns")

	var job: NumericComputeJob = NumericComputeJob.new()
	job.capture(data, engine.config, 1.0 / 30.0)
	_receive(job)
	entities.capture(data.index.handles[0])
	entities.remove_expired()
	var position := data.motion.position.duplicate()
	_check(not job.commit(data) and data.motion.position == position, "row swap rejects stale output atomically")
	var corpse_row := data.index.active_count
	var corpse_position := data.motion.position[corpse_row]
	entities.update_movement(1.0 / 30.0)
	_check(data.motion.position[corpse_row] == corpse_position, "bulk movement retains corpse suffix")

func _timers() -> void:
	var data: AnimalData = engine.data_service.animals
	engine.config.sheep.wander_weight = 0.0
	for duration in [0.0, 2.0]:
		engine.config.sheep.panic_duration = duration
		for row in range(data.index.active_count):
			data.motion.wander_remaining[row] = 0.01
			data.memory.perception_remaining[row] = -0.1
			data.sheep.panic_strength[row] = 0.5
		engine.animal_service.advance_time(1.0 / 30.0)
		for row in range(data.index.active_count):
			_check(absf(data.memory.perception_remaining[row] - (-0.1 - 1.0 / 30.0)) < 0.000001, "CPU perception timer crosses zero")
			if data.identity.kind[row] == AnimalEntity.Kind.SHEEP:
				_check(absf(data.motion.wander_remaining[row] - (0.01 - 1.0 / 30.0)) < 0.000001, "CPU wander crosses zero")
				var expected: float = maxf(0.0, 0.5 - (1.0 / 30.0) / duration) if duration > 0.0 else 0.0
				_check(absf(data.sheep.panic_strength[row] - expected) < 0.000001, "CPU panic preserves zero-duration semantics")

func _random_sequence() -> void:
	var expected: Array = []
	var data: AnimalData = engine.data_service.animals
	for repetition in range(2):
		engine.reset_simulation()
		engine.paused = true
		engine.config.sheep.wander_weight = 1.0
		engine.entity_service.spawn(AnimalEntity.Kind.SHEEP, 2, Vector2(400, 300))
		for row in range(data.index.active_count):
			data.motion.wander_remaining[row] = 1.5
			data.motion.wander_point[row] = Vector2(100, 100)
		for step in range(100):
			engine.animal_service.advance_time(1.0 / 30.0)
			var value := [engine.rng.state, data.motion.wander_point.duplicate(), data.motion.wander_remaining.duplicate()]
			if repetition == 0:
				expected.append(value)
			else:
				_check(value == expected[step], "CPU timers preserve RNG and wander sequence at step %d" % step)

func _interactions() -> void:
	var data: AnimalData = engine.data_service.animals
	var entities: EntityService = engine.entity_service
	for approaching in [true, false]:
		engine.reset_simulation()
		engine.paused = true
		var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(420, 300))[0]
		var wolf := entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400 if approaching else 410, 300))[0]
		engine.config.wolf.capture_distance = 15.0
		data.motion.facing[wolf.row] = Vector2.RIGHT
		data.motion.intent[wolf.row] = AnimalData.MotionIntent.POINT
		data.motion.movement_goal[wolf.row] = Vector2(420, 300)
		data.motion.speed_limit[wolf.row] = 1000.0 if approaching else 0.0
		data.motion.desired_velocity[sheep.row] = Vector2.ZERO if approaching else Vector2(1000, 0)
		data.motion.speed_limit[sheep.row] = 1000.0
		data.wolf.hunting[wolf.row] = 1
		data.memory.target[wolf.row] = sheep
		data.brain.current_behavior[wolf.row] = AnimalEntity.Behavior.CHASE
		entities.update_movement(0.02)
		engine.wolf_system.resolve_interactions(wolf, 0.02)
		_check(bool(data.identity.alive[sheep.row]) != approaching, "interaction uses this step's GPU positions when entering or leaving capture range")

func _queue() -> void:
	var service: ComputeShaderService = ComputeShaderService.new()
	root.add_child(service)
	service.startup()
	var job: HeldSheep = HeldSheep.new()
	job.snapshot = GridAggregateJob.capture_snapshot(PackedInt32Array([0]))
	job.grid = GridAggregateJob.build_snapshot(job.snapshot)
	_check(service.submit(job), "background sheep request accepted")
	job.entered.wait()
	var compute: ComputeShaderService = engine.compute_service
	engine.compute_service = service
	var release := WorkerThreadPool.add_task(job.gate.post)
	var data: AnimalData = engine.data_service.animals
	_check(_run_movement(service, data, 1.0 / 30.0), "foreground movement follows an in-flight sheep request")
	WorkerThreadPool.wait_for_task_completion(release)
	_check(job.state == Job.State.COMPLETED and service.busy, "movement wait leaves sheep completion unapplied")
	_check(_run_movement(service, data, 1.0 / 30.0), "completed sheep result does not occupy foreground slot")
	var completed := service._take_completed()
	_check(completed == job, "sheep completion remains available for step-start flush")
	engine.compute_service = compute
	service.shutdown()
	service.queue_free()

func _failures() -> void:
	var service: FailedNumeric = FailedNumeric.new()
	root.add_child(service)
	service.startup()
	var data: AnimalData = engine.data_service.animals
	var position := data.motion.position.duplicate()
	_check(not _run_movement(service, data, 1.0 / 30.0), "GPU error fails instead of selecting CPU")
	_check(data.motion.position == position and not service.available(), "failed GPU leaves movement untouched and disables submissions")
	service.shutdown()
	service.queue_free()

func _run() -> void:
	scene = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	scene.simulation_config = scene.simulation_config.copy_config()
	scene.simulation_config.initial_total = 0
	scene.simulation_config.arena_size = Vector2(1280, 720)
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	if engine.entity_service == null or not engine.running:
		_check(false, "simulation initializes")
		quit(1)
		return
	engine.set_process(false)
	engine.paused = true
	engine.compute_service.shutdown()
	engine.compute_service.startup()
	if DisplayServer.get_name() == "headless":
		_check(not engine.compute_service.available(), "headless refuses GPU passes")
	else:
		_check(engine.compute_service.available(), "windowed RD available")
		_movement()
		_timers()
		_random_sequence()
		_interactions()
		engine.entity_service.spawn(AnimalEntity.Kind.SHEEP, 2, Vector2(400, 300))
		_queue()
		_failures()
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	print("NUMERIC_COMPUTE_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _run_movement(service: ComputeShaderService, storage: AnimalData, interval: float) -> bool:
	var previous: ComputeShaderService = engine.compute_service
	engine.compute_service = service
	var job: NumericComputeJob = FailedNumericJob.new() if service is FailedNumeric else NumericComputeJob.new()
	job.capture(storage, engine.config, interval)
	var result := job.run()
	engine.compute_service = previous
	return result
