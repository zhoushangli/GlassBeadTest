extends SceneTree

const ReferenceSimulation = preload("res://Tests/ReferenceSimulation.gd")

class GateJob extends Job:
	var gate: Semaphore = Semaphore.new()
	var entered: Semaphore = Semaphore.new()
	var block: bool = true
	var applications: int = 0
	var worker: bool = false
	var value: int = 0
	var input_value: int = 0

	func execute() -> void:
		worker = not Thread.is_main_thread()
		entered.post()
		if block:
			gate.wait()
		value = input_value

	func apply_result() -> void:
		applications += 1

class HeldCompute extends ComputeShaderService:

	func _supports_device() -> bool:
		return true

	func _initialize_device() -> void:
		pass

class HeldSheep extends SheepComputeJob:
	var entered: Semaphore = Semaphore.new()
	var gate: Semaphore = Semaphore.new()

	func _execute_gpu() -> PackedByteArray:
		entered.post()
		gate.wait()
		return PackedByteArray()

class FailedCompute extends ComputeShaderService:
	func _supports_device() -> bool:
		return true

	func _initialize_device() -> void:
		pass

class FailedSheep extends SheepComputeJob:
	func _execute_gpu() -> PackedByteArray:
		error = "Injected readback failure"
		return PackedByteArray()

class FailedInitialization extends ComputeShaderService:
	func _supports_device() -> bool:
		return true

	func _initialize_device() -> void:
		_failure = "Injected device initialization failure"

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node
var authored: SimulationConfig
var verification_directory: String

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _wait(job: Job) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while job.task_id >= 0 and not WorkerThreadPool.is_task_completed(job.task_id) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
	_check(job.task_id < 0 or WorkerThreadPool.is_task_completed(job.task_id), "worker completes within test deadline")

func _empty() -> void:
	engine.config = authored.copy_config()
	engine.config.initial_total = 0
	engine.reset_simulation()
	engine.paused = true

func _job(kind: AnimalEntity.Kind) -> Job:
	ReferenceSimulation.rebuild(engine.grid_service)
	var job: Job = WolfPerceptionJob.new() if kind == AnimalEntity.Kind.WOLF else DogPerceptionJob.new()
	job.stage = &"Wolf" if kind == AnimalEntity.Kind.WOLF else &"Dog"
	job.snapshot = GridAggregateJob.capture_snapshot()
	job.grid = ReferenceSimulation.build_snapshot(job.snapshot)
	job.rows = job.snapshot.rows_for(kind)

	return job

func _queues() -> void:
	var service: JobService = JobService.new()
	root.add_child(service)
	service.startup()
	service.max_workers = 1
	var first: GateJob = GateJob.new()
	first.stage = &"Wolf"
	first.input_value = 17
	_check(service.submit_async(first), "async request accepted")
	first.entered.wait()
	service.flush()
	_check(first.applications == 0 and first.state == Job.State.WORKING, "flush returns while worker is held behind gate")
	_check(not service.submit_async(first), "in-flight request cannot be submitted twice")
	var dog: GateJob = GateJob.new()
	dog.stage = &"Dog"
	dog.block = false
	_check(service.submit_async(dog) and dog.state == Job.State.PENDING, "other species queues within worker limit")
	var sync: GateJob = GateJob.new()
	sync.stage = &"Sheep"
	sync.block = false
	service.add_job(sync)
	service.finish_stage()
	_check(sync.applications == 1 and first.applications == 0, "synchronous stage runs without waiting for async worker")
	service.reset()
	_check(first.state == Job.State.WORKING and dog.state == Job.State.DISCARDED, "reset retires working request and discards pending without waiting")
	first.gate.post()
	_wait(first)
	service.flush()
	_check(first.state == Job.State.DISCARDED and first.applications == 0 and first.worker, "invalidated worker is reclaimed without application")
	var completed: GateJob = GateJob.new()
	completed.stage = &"Dog"
	completed.block = false
	service.submit_async(completed)
	_wait(completed)
	_check(completed.applications == 0, "completed result waits for explicit flush")
	service.flush()
	service.flush()
	_check(completed.applications == 1 and completed.task_id == -1, "flush applies and reclaims exactly once")
	service.shutdown()
	service.queue_free()

func _snapshots() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data: AnimalData = engine.data_service.animals
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(550, 300))[0]
	var wolf := entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400, 300))[0]
	data.motion.facing[wolf.row] = Vector2.RIGHT
	var job := _job(AnimalEntity.Kind.WOLF)
	var point: Vector2 = job.snapshot.motion.position[sheep.row]
	var grid_point: Vector2 = job.grid.cells.positions[sheep.row]
	data.motion.position[sheep.row] = Vector2(50, 300)
	ReferenceSimulation.rebuild(engine.grid_service)
	_check(job.snapshot.motion.position[sheep.row] == point and job.grid.cells.positions[sheep.row] == grid_point, "job owns immutable entity and grid input")
	engine.job_service.submit_async(job)
	_wait(job)
	_check((job as WolfPerceptionJob).prey_rows[0] == sheep.row, "worker selects from submitted snapshot despite live motion")
	_check(not data.wolf.hunting[wolf.row], "worker does not mutate live state")
	engine.paused = true
	engine._process(0.0)
	_check(not data.wolf.hunting[wolf.row], "paused frames do not commit completed results")
	engine.request_single_step()
	engine._process(0.0)
	_check(data.wolf.hunting[wolf.row] and data.memory.target[wolf.row] == sheep, "single step commits valid result at step start")

	_empty()
	sheep = entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(550, 300))[0]
	wolf = entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400, 300))[0]
	data.motion.facing[wolf.row] = Vector2.RIGHT
	job = _job(AnimalEntity.Kind.WOLF)
	engine.job_service.submit_async(job)
	_wait(job)
	entities.capture(sheep)
	entities.remove_expired(10.0)
	var replacement := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(550, 300))[0]
	_check(Job.new().snapshot_animal(job.snapshot, 0) == null, "reused slot rejects previous AnimalID")
	engine.job_service.flush()
	_check(not data.wolf.hunting[wolf.row] and data.memory.target[wolf.row] != replacement, "dead prey result cannot target replacement after row swaps")
	var fresh := _job(AnimalEntity.Kind.WOLF)
	engine.job_service.submit_async(fresh)
	_wait(fresh)
	engine.job_service.flush()
	_check(data.memory.target[wolf.row] == replacement, "fresh snapshot resolves wolf current row after structural changes")
	job = _job(AnimalEntity.Kind.WOLF)
	engine.job_service.submit_async(job)
	_wait(job)
	engine.reset_simulation()
	engine.job_service.flush()
	_check(job.state == Job.State.DISCARDED and data.index.active_count == 0, "reset discards completed old-world result")

func _shared_inputs() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	entities.spawn(AnimalEntity.Kind.SHEEP, 3, Vector2(300, 300))
	entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(450, 300))
	entities.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(300, 350))
	entities.capture(engine.data_service.animals.index.handles[0])
	entities.remove_expired(10.0)
	var snapshot: AnimalSnapshot = GridAggregateJob.capture_snapshot(PackedInt32Array([0]))
	_check(snapshot.motion.position.size() == engine.data_service.animals.index.active_count and snapshot.identity.animal_id.size() == engine.data_service.animals.index.active_count, "capture excludes inactive retained rows")
	_check(snapshot.memory.target.is_empty() and snapshot.dog.returning.is_empty() and snapshot.wolf.resting.is_empty(), "sheep-only capture omits wolf and dog decision columns")
	var grid := ReferenceSimulation.build_snapshot(snapshot)
	var point := snapshot.motion.position[0]
	grid.cells.positions[0] = point + Vector2.ONE
	_check(snapshot.motion.position[0] == point + Vector2.ONE and engine.data_service.animals.motion.position[0] == point, "grid aliases the isolated snapshot position column")
	grid.cells.positions[0] = point
	var members := grid.cells.members.duplicate()
	GridAggregateJob.publish_grid(grid)
	engine.grid_service.reset()
	_check(grid.cells.positions.size() == engine.data_service.animals.index.active_count and grid.cells.members == members and not grid.pressure.needed.is_empty(), "grid reset replaces service arrays without clearing published input")
	var first: GateJob = GateJob.new()
	var second: GateJob = GateJob.new()
	first.stage = &"Wolf"
	second.stage = &"Dog"
	first.block = false
	second.block = false
	first.snapshot = snapshot
	second.snapshot = snapshot
	first.grid = grid
	second.grid = grid
	engine.job_service.submit_async(first)
	engine.job_service.submit_async(second)
	_wait(first)
	_wait(second)
	_check(first.snapshot == second.snapshot and first.grid == second.grid and first.sequence != second.sequence, "jobs share input objects and retain separate submission metadata")
	engine.job_service.flush()
	var weight := snapshot.config.sheep.wander_weight
	engine.config.sheep.wander_weight = weight + 0.5
	_check(snapshot.config.sheep.wander_weight == weight, "published configuration is isolated from live edits")
	engine.animal_service.refresh_config()
	var fresh: AnimalSnapshot = GridAggregateJob.capture_snapshot()
	_check(fresh.config != snapshot.config and fresh.config.sheep.wander_weight == weight + 0.5, "configuration refresh publishes a new version")

func _compute_job(failed: bool = false) -> SheepComputeJob:
	var job: SheepComputeJob = FailedSheep.new() if failed else HeldSheep.new()
	job.snapshot = GridAggregateJob.capture_snapshot()
	job.grid = ReferenceSimulation.build_snapshot(job.snapshot)
	return job

func _compute_cancellation() -> void:
	_empty()
	engine.entity_service.spawn(AnimalEntity.Kind.SHEEP, 2, Vector2(300, 300))
	var held: HeldCompute = HeldCompute.new()
	root.add_child(held)
	held.startup()
	var job := _compute_job()
	_check(held.submit(job), "device service accepts one request")
	(job as HeldSheep).entered.wait()
	_check(not held.submit(_compute_job()), "busy device rejects another request")
	var worker_limit: int = engine.job_service.max_workers
	engine.job_service.max_workers = 1
	var cpu_job: GateJob = GateJob.new()
	cpu_job.stage = &"Wolf"
	cpu_job.block = false
	_check(engine.job_service.submit_async(cpu_job), "CPU work can be submitted while GPU is blocked")
	_wait(cpu_job)
	engine.job_service.flush()
	_check(cpu_job.applications == 1 and held.busy, "blocked GPU occupies no shared worker slot")
	engine.job_service.max_workers = worker_limit
	held.reset()
	_check(job.is_cancelled() and held.busy, "reset cancels without waiting for device work")
	(job as HeldSheep).gate.post()
	var deadline := Time.get_ticks_msec() + 5000
	while held.busy and Time.get_ticks_msec() < deadline:
		held._process(0.0)
		OS.delay_msec(1)
	_check(job.state == Job.State.DISCARDED and job.snapshot == null and job.metrics.decode_ms == 0.0, "paused service retires cancelled work without decoding")
	job = _compute_job()
	job.cancel()
	_check(not held.submit(job), "cancelled request is rejected before execution")
	held.shutdown()
	held.startup()
	_check(held.available() and not held.busy, "service restarts after shutdown")
	job = _compute_job()
	_check(held.submit(job), "restarted device accepts input")
	(job as HeldSheep).entered.wait()
	job.cancel()
	var release_task := WorkerThreadPool.add_task((job as HeldSheep).gate.post)
	held.shutdown()
	WorkerThreadPool.wait_for_task_completion(release_task)
	_check(job.state == Job.State.DISCARDED and not held.busy, "shutdown joins device work without a main-thread completion callback")
	held.shutdown()
	held.queue_free()
	var failed: FailedCompute = FailedCompute.new()
	root.add_child(failed)
	failed.startup()
	var original: ComputeShaderService = engine.compute_service
	engine.compute_service = failed
	job = _compute_job(true)

	engine.data_service.decisions.waiting[0] = true
	_check(failed.submit(job), "failure fixture accepts input")
	deadline = Time.get_ticks_msec() + 5000
	var failed_result: SheepComputeJob
	while failed_result == null and Time.get_ticks_msec() < deadline:
		failed_result = failed._take_completed()
		OS.delay_msec(1)
	_check(failed_result == job and not failed.failure.is_empty(), "device error returns failed completion")
	_check(not failed.available(), "failed device refuses subsequent GPU submissions")
	job.release_input()
	engine.data_service.decisions.waiting.clear()
	engine.compute_service = original
	failed.shutdown()
	failed.queue_free()
	var unavailable: FailedInitialization = FailedInitialization.new()
	root.add_child(unavailable)
	unavailable.startup()
	_check(not unavailable.available() and not unavailable.failure.is_empty(), "initialization failure is reported before requests are accepted")
	unavailable.shutdown()
	unavailable.queue_free()

func _frequency_and_motion() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data: AnimalData = engine.data_service.animals
	var wolf := entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400, 300))[0]
	var dog := entities.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(800, 500))[0]
	engine.config.wolf_update_hz = 25
	engine.config.sheepdog_update_hz = 15
	for step in range(60):
		engine.simulate_step(1.0 / 60.0)
		while not engine.job_service.async_jobs.is_empty() or engine.compute_service.busy:
			for job: Job in engine.job_service.async_jobs.values():
				_wait(job)
			engine.animal_service.apply_completed()
			OS.delay_msec(1)
	_check(engine.data_service.decisions.requested[1] == 25 and engine.data_service.decisions.requested[2] == 15, "non-divisor and independent frequencies preserve fractional time")
	engine.job_service.invalidate_async()
	engine.data_service.decisions.waiting.clear()
	var blocked: GateJob = GateJob.new()
	blocked.stage = &"Wolf"
	engine.job_service.submit_async(blocked)
	blocked.entered.wait()
	var previous := data.motion.position[wolf.row]
	data.motion.intent[wolf.row] = AnimalData.MotionIntent.POINT
	data.motion.movement_goal[wolf.row] = Vector2(900, 300)
	data.motion.speed_limit[wolf.row] = 60.0
	for step in range(6):
		engine.simulate_step(1.0 / 60.0)
		_check(data.motion.position[wolf.row].distance_to(previous) > 0.0, "movement continues while selection is blocked")
		previous = data.motion.position[wolf.row]
	_check(engine.job_service.async_jobs[&"Wolf"] == blocked, "busy species does not accumulate requests")
	blocked.gate.post()
	_wait(blocked)
	engine.job_service.invalidate_async()
	data.brain.current_behavior[wolf.row] = AnimalEntity.Behavior.STALK
	data.wolf.strategy[wolf.row] = AnimalEntity.Strategy.SIDE
	data.memory.last_seen_position[wolf.row] = Vector2(600, 300)
	data.memory.last_seen_velocity[wolf.row] = Vector2.RIGHT
	data.motion.intent[wolf.row] = AnimalData.MotionIntent.POINT
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(600, 400))[0]
	data.brain.current_behavior[dog.row] = AnimalEntity.Behavior.COLLECT
	data.dog.collected_sheep[dog.row] = sheep
	data.dog.protection_center[dog.row] = Vector2(500, 400)
	data.motion.intent[dog.row] = AnimalData.MotionIntent.POINT
	ReferenceSimulation.new(engine.data_service.animals).update_all_steering(1.0 / 60.0)
	var goals := [data.motion.movement_goal[wolf.row], data.motion.movement_goal[dog.row]]
	for step in range(6):
		ReferenceSimulation.new(engine.data_service.animals).update_all_steering(1.0 / 60.0)
	_check(goals == [data.motion.movement_goal[wolf.row], data.motion.movement_goal[dog.row]], "stalk and collect offsets never accumulate between decisions")
	engine.paused = false
	engine.profile_service.set_performance_stats_enabled(false)
	engine.reset_frequency_window()
	engine._frequency_steps = 20
	engine._frequency_started -= 1000000
	engine.update_frequency()
	_check(engine.actual_simulation_hz > 19.0 and engine.actual_simulation_hz < 21.0, "actual Hz counts executed steps independently of target and profiler")
	engine.paused = true
	scene.hud.refresh()
	_check(scene.hud.metrics.text.contains("Paused"), "HUD distinguishes paused simulation")

func _configuration() -> void:
	var settings: SimulationConfig = SimulationConfig.new()
	_check(settings.max_steps_per_frame == 4, "old presets acquire default step limit")
	settings.max_steps_per_frame = 0
	_check(not settings.validate().is_empty(), "config rejects nonpositive step limit")
	settings.max_steps_per_frame = 7
	_check(settings.simulation_hz == 60.0 and settings.sheep_update_hz == 24 and settings.wolf_update_hz == 12 and settings.sheepdog_update_hz == 12, "configuration supplies clock and decision defaults")
	settings.simulation_hz = 15.0
	_check(not settings.validate().is_empty(), "decision frequency cannot exceed simulation rate")
	settings.simulation_hz = 90.0
	settings.wolf_update_hz = 15
	settings.sheepdog_update_hz = 25
	var blocked: GateJob = GateJob.new()
	blocked.stage = &"Wolf"
	engine.job_service.invalidate_async()
	engine.job_service.submit_async(blocked)
	blocked.entered.wait()
	engine.request_config_apply(settings)
	var version: int = engine.job_service.async_version
	engine._process(0.0)
	_check(engine.job_service.async_version > version and engine.config.simulation_hz == 90.0, "hot configuration invalidates requests and applies clock")
	_check(engine.config.max_steps_per_frame == 7, "hot configuration applies step limit")
	blocked.gate.post()
	_wait(blocked)
	engine.job_service.flush()
	_check(blocked.applications == 0 and blocked.state == Job.State.DISCARDED, "configuration change cannot commit an in-flight old request")
	var path := verification_directory.path_join("test-preset.tres")
	_check(engine.save_preset(path) == OK, "frequency preset saves")
	var loaded: SimulationConfig = engine.load_preset(path)
	_check(loaded != null and loaded.simulation_hz == 90.0 and loaded.wolf_update_hz == 15 and loaded.sheepdog_update_hz == 25, "frequency preset round trips")
	_check(loaded != null and loaded.max_steps_per_frame == 7, "step limit preset round trips")
	scene.hud.parameters.set_draft(engine.config)
	_check(scene.hud.parameters.editors.has("World.max_steps_per_frame"), "runtime panel exposes step limit")
	_check(scene.hud.parameters.editors.has("World.simulation_hz") and scene.hud.parameters.editors.has("World.wolf_update_hz") and scene.hud.parameters.editors.has("World.sheepdog_update_hz"), "runtime panel exposes all frequencies")

func _timers_and_invalidation() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data: AnimalData = engine.data_service.animals
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(550, 300))[0]
	var wolf := entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400, 300))[0]
	var dog := entities.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(800, 500))[0]
	data.motion.facing[wolf.row] = Vector2.RIGHT
	engine.wolf_system.begin_hunt(wolf, sheep)
	engine.config.wolf.memory_duration = 0.0
	engine.wolf_system.advance_time(1.0 / 60.0)
	_check(data.wolf.hunting[wolf.row], "zero memory duration preserves currently visible prey")
	data.memory.target_visible[wolf.row] = 0
	engine.wolf_system.advance_time(1.0 / 60.0)
	_check(not data.wolf.hunting[wolf.row] and data.wolf.resting[wolf.row], "zero memory duration ends unseen hunt without waiting for worker")
	var elapsed := data.wolf.howl_elapsed[wolf.row]
	engine.wolf_system.advance_time(0.5)
	_check(is_equal_approx(data.wolf.howl_elapsed[wolf.row], elapsed + 0.5), "cooldown advances by simulation time independently of decisions")
	data.dog.protected_sheep[dog.row] = sheep
	data.dog.collected_sheep[dog.row] = sheep
	data.brain.current_behavior[dog.row] = AnimalEntity.Behavior.COLLECT
	entities.capture(sheep)
	entities.remove_expired()
	engine.dog_system.advance_time(1.0 / 60.0)
	_check(data.dog.protected_sheep[dog.row] == null and data.dog.collected_sheep[dog.row] == null and data.brain.current_behavior[dog.row] == AnimalEntity.Behavior.PATROL, "lost dog anchor clears stale assignment and resumes patrol immediately")

func _run() -> void:
	verification_directory = "res://output/service-refactor/async-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(verification_directory)
	_queues()
	scene = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	scene.simulation_config = scene.simulation_config.copy_config()
	scene.simulation_config.initial_total = 276
	scene.simulation_config.arena_size = Vector2(1280, 720)
	scene.simulation_config.simulation_hz = 60.0
	scene.simulation_config.sheep_update_hz = 24
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	authored = engine.config.copy_config()
	_snapshots()
	_shared_inputs()
	_compute_cancellation()
	_frequency_and_motion()
	_timers_and_invalidation()
	_configuration()
	if DisplayServer.get_name() != "headless":
		engine.request_config_apply(authored)
		engine._process(0.0)
		engine.paused = false
		engine.set_process(true)
		await create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(verification_directory.path_join("running.png"))
		_check(error == OK and engine.actual_simulation_hz > 0.0, "running scene renders HUD with measured simulation frequency")
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	print("ASYNC_DECISION_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
