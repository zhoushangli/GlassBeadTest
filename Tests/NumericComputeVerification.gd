extends SceneTree

class HeldDevice extends ComputeShaderService:
	var entered := Semaphore.new()
	var gate := Semaphore.new()

	func execute_gpu(job: SheepComputeJob) -> PackedByteArray:
		entered.post()
		gate.wait()
		return super.execute_gpu(job)

class FailedNumeric extends ComputeShaderService:
	func _supports_device() -> bool:
		return true

	func _initialize_device() -> void:
		pass

	func execute_numeric_gpu(job: NumericComputeJob) -> PackedByteArray:
		job.error = "Injected numeric failure"
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
	job.compute = compute
	compute._mutex.lock()
	compute._sequence += 1
	job.sequence = compute._sequence
	job.submitted_usec = Time.get_ticks_usec()
	job.state = Job.State.PENDING
	compute._foreground = job
	compute._mutex.unlock()
	compute._wake.post()
	job.completed.wait()
	_check(job.error.is_empty() and job.metrics.gpu_ms >= 0.0, "GPU pass completes with timestamps")

func _movement() -> void:
	var entities: EntityService = engine.entity_service
	var data := entities.data
	for pass_kind in [NumericComputeJob.Pass.MOVEMENT, NumericComputeJob.Pass.TIMERS]:
		var empty := NumericComputeJob.new()
		empty.capture(data, engine.config, 1.0 / 30.0, pass_kind)
		_receive(empty)
		_check(empty.commit(data), "empty GPU pass retains inactive columns")
	for amount in [1, 15, 130]:
		engine.reset_simulation()
		engine.paused = true
		entities.spawn(AnimalEntity.Kind.SHEEP, amount)
		entities.spawn(AnimalEntity.Kind.WOLF, 3)
		entities.spawn(AnimalEntity.Kind.SHEEPDOG, 2)
		for row in range(data.active_count):
			data.motion_intent[row] = row % 3
			data.motion_position[row] = Vector2(12, 94) if row % 4 == 0 else Vector2(1268, 662)
			data.motion_velocity[row] = Vector2(-130, 40)
			data.motion_desired_velocity[row] = Vector2(80, -200)
			data.motion_speed_limit[row] = 0.0 if row % 7 == 0 else 100.0
			data.motion_movement_goal[row] = data.motion_position[row] if row % 5 == 0 else Vector2(600, 300)
			data.motion_separation[row] = Vector2(-0.2, 0.3)
		for interval in [0.0, 1.0 / 30.0, 0.2]:
			var job := NumericComputeJob.new()
			job.capture(data, engine.config, interval, NumericComputeJob.Pass.MOVEMENT)
			entities.update_movement(interval)
			var expected := [data.motion_position.duplicate(), data.motion_velocity.duplicate(), data.motion_facing.duplicate(), data.motion_desired_velocity.duplicate()]
			_receive(job)
			for column in range(4):
				for row in range(data.active_count):
					_check(job.output[column][row].distance_to(expected[column][row]) <= 0.015, "movement matches CPU column %d row %d" % [column, row])
			_check(job.commit(data), "matching step commits movement columns")

	var job := NumericComputeJob.new()
	job.capture(data, engine.config, 1.0 / 30.0, NumericComputeJob.Pass.MOVEMENT)
	_receive(job)
	entities.capture(data.handles[0])
	entities.remove_expired()
	var position := data.motion_position.duplicate()
	_check(not job.commit(data) and data.motion_position == position, "row swap rejects stale output atomically")
	var corpse_row := data.active_count
	var corpse_position := data.motion_position[corpse_row]
	engine.compute_service.movement_backend = "gpu"
	entities.update_movement(1.0 / 30.0)
	_check(data.motion_position[corpse_row] == corpse_position, "bulk movement retains corpse suffix")
	engine.compute_service.movement_backend = "cpu"

func _timers() -> void:
	var data: AnimalData = engine.entity_service.data
	for duration in [0.0, 2.0]:
		engine.config.sheep.panic_duration = duration
		for row in range(data.active_count):
			data.motion_wander_remaining[row] = 0.01
			data.memory_perception_remaining[row] = -0.1
			data.sheep_panic_strength[row] = 0.01 if row % 2 == 0 else 0.5
		var job := NumericComputeJob.new()
		job.capture(data, engine.config, 1.0 / 30.0, NumericComputeJob.Pass.TIMERS)
		_receive(job)
		for row in range(data.active_count):
			_check(absf(job.output[0][row] - (0.01 - 1.0 / 30.0)) < 0.000001, "wander crosses zero")
			_check(absf(job.output[1][row] - (-0.1 - 1.0 / 30.0)) < 0.000001, "negative perception timer remains negative")
			var panic := data.sheep_panic_strength[row]
			if data.identity_kind[row] == AnimalEntity.Kind.SHEEP:
				panic = maxf(0.0, panic - (1.0 / 30.0) / duration) if duration > 0.0 else 0.0
			_check(absf(job.output[2][row] - panic) < 0.000001, "panic matches CPU including zero duration")
		_check(job.commit(data), "timer columns commit")

func _random_sequence() -> void:
	var expected: Array = []
	var data: AnimalData = engine.entity_service.data
	for backend in ["cpu", "gpu"]:
		engine.reset_simulation()
		engine.paused = true
		engine.config.sheep.wander_weight = 1.0
		engine.entity_service.spawn(AnimalEntity.Kind.SHEEP, 2, Vector2(400, 300))
		for row in range(data.active_count):
			data.motion_wander_remaining[row] = 1.5
			data.motion_wander_point[row] = Vector2(100, 100)
		engine.compute_service.timers_backend = backend
		for step in range(100):
			engine.animal_service.advance_time(1.0 / 30.0)
			var value := [engine.rng.state, data.motion_wander_point.duplicate(), data.motion_wander_remaining.duplicate()]
			if backend == "cpu":
				expected.append(value)
			else:
				_check(value == expected[step], "float64 timers preserve RNG and wander sequence at step %d" % step)
	engine.compute_service.timers_backend = "cpu"

func _interactions() -> void:
	var data: AnimalData = engine.entity_service.data
	var entities: EntityService = engine.entity_service
	engine.compute_service.movement_backend = "gpu"
	for approaching in [true, false]:
		engine.reset_simulation()
		engine.paused = true
		var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(420, 300))[0]
		var wolf := entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400 if approaching else 410, 300))[0]
		engine.config.wolf.capture_distance = 15.0
		data.motion_facing[wolf.row] = Vector2.RIGHT
		data.motion_intent[wolf.row] = AnimalData.MotionIntent.POINT
		data.motion_movement_goal[wolf.row] = Vector2(420, 300)
		data.motion_speed_limit[wolf.row] = 1000.0 if approaching else 0.0
		data.motion_desired_velocity[sheep.row] = Vector2.ZERO if approaching else Vector2(1000, 0)
		data.motion_speed_limit[sheep.row] = 1000.0
		data.wolf_hunting[wolf.row] = 1
		data.memory_target[wolf.row] = sheep
		data.brain_current_behavior[wolf.row] = AnimalEntity.Behavior.CHASE
		entities.update_movement(0.02)
		engine.wolf_system.resolve_interactions(wolf, 0.02)
		_check(bool(data.identity_alive[sheep.row]) != approaching, "interaction uses this step's GPU positions when entering or leaving capture range")
	engine.compute_service.movement_backend = "cpu"

func _queue() -> void:
	var service := HeldDevice.new()
	root.add_child(service)
	service.backend = "gpu"
	service.startup()
	var job := SheepComputeJob.new()
	job.snapshot = engine.animal_system.decision_snapshot(PackedInt32Array([0]), true)
	job.grid = GridService.build_snapshot(job.snapshot, false)
	_check(service.submit(job), "background sheep request accepted")
	service.entered.wait()
	var compute: ComputeShaderService = engine.compute_service
	engine.compute_service = service
	var release := WorkerThreadPool.add_task(service.gate.post)
	service.movement_backend = "gpu"
	var data: AnimalData = engine.entity_service.data
	_check(service.run_numeric(data, 1.0 / 30.0, NumericComputeJob.Pass.MOVEMENT) == 1, "foreground movement follows an in-flight sheep request")
	WorkerThreadPool.wait_for_task_completion(release)
	_check(job.state == Job.State.COMPLETED and service.busy, "movement wait leaves sheep completion unapplied")
	_check(service.run_numeric(data, 1.0 / 30.0, NumericComputeJob.Pass.MOVEMENT) == 1, "completed sheep result does not occupy foreground slot")
	var completed := service._take_completed()
	_check(completed == job, "sheep completion remains available for step-start flush")
	engine.compute_service = compute
	service.shutdown()
	service.queue_free()

func _failures() -> void:
	var original: ComputeShaderService = engine.compute_service
	var service := FailedNumeric.new()
	root.add_child(service)
	service.startup()
	engine.compute_service = service
	var data: AnimalData = engine.entity_service.data
	service.movement_backend = "auto"
	var position := data.motion_position.duplicate()
	_check(service.run_numeric(data, 1.0 / 30.0, NumericComputeJob.Pass.MOVEMENT) == 0 and data.motion_position == position, "auto returns untouched input to CPU fallback")
	_check(service.available(), "numeric failure does not disable other kernels")
	service.movement_backend = "gpu"
	var step: int = engine.step_count
	engine.simulate_step(1.0 / 30.0)
	_check(engine.step_failed and engine.paused and engine.step_count == step, "forced GPU failure pauses without completing an inconsistent step")
	var timer := data.motion_wander_remaining.duplicate()
	engine.simulate_step(1.0 / 30.0)
	_check(data.motion_wander_remaining == timer, "failed step cannot partially advance again before reset")
	engine.compute_service = original
	service.shutdown()
	service.queue_free()
	engine.reset_simulation()
	_check(not engine.step_failed, "reset clears failed-step latch")

func _run() -> void:
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
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
	engine.compute_service.movement_backend = "cpu"
	engine.compute_service.backend = "gpu"
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
