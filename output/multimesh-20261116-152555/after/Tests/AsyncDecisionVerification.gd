extends SceneTree

class GateJob extends Job:
	var gate := Semaphore.new()
	var entered := Semaphore.new()
	var block: bool = true
	var applications: int = 0
	var worker: bool = false

	func execute() -> void:
		worker = not Thread.is_main_thread()
		entered.post()
		if block:
			gate.wait()
		result.value = context.get("value", 0)

	func apply_result() -> void:
		applications += 1

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
	engine.grid_service.rebuild()
	var job: Job = WolfPerceptionJob.new() if kind == AnimalEntity.Kind.WOLF else DogPerceptionJob.new()
	job.stage = &"Wolf" if kind == AnimalEntity.Kind.WOLF else &"Dog"
	job.context = engine.animal_system.decision_snapshot(kind)
	job.rows = job.context.rows
	job.target = engine.wolf_system if kind == AnimalEntity.Kind.WOLF else engine.dog_system
	return job

func _queues() -> void:
	var service := JobService.new()
	root.add_child(service)
	service.startup()
	service.max_workers = 1
	var first := GateJob.new()
	first.stage = &"Wolf"
	first.context.value = 17
	_check(service.submit_async(first), "async request accepted")
	first.entered.wait()
	service.flush()
	_check(first.applications == 0 and first.state == Job.State.WORKING, "flush returns while worker is held behind gate")
	_check(not service.submit_async(first), "in-flight request cannot be submitted twice")
	var dog := GateJob.new()
	dog.stage = &"Dog"
	dog.block = false
	_check(service.submit_async(dog) and dog.state == Job.State.PENDING, "other species queues within worker limit")
	var sync := GateJob.new()
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
	var completed := GateJob.new()
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
	var data := entities.data
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(550, 300))[0]
	var wolf := entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400, 300))[0]
	data.motion_facing[wolf.row] = Vector2.RIGHT
	var job := _job(AnimalEntity.Kind.WOLF)
	var point: Vector2 = job.context.motion_position[sheep.row]
	var grid_point: Vector2 = job.context.grid.positions[sheep.row]
	data.motion_position[sheep.row] = Vector2(50, 300)
	engine.grid_service.rebuild()
	_check(job.context.motion_position[sheep.row] == point and job.context.grid.positions[sheep.row] == grid_point, "job owns immutable entity and grid input")
	engine.job_service.submit_async(job)
	_wait(job)
	_check(job.result.entries[0].prey == sheep.row, "worker selects from submitted snapshot despite live motion")
	_check(not data.wolf_hunting[wolf.row], "worker does not mutate live state")
	engine.paused = true
	engine._process(0.0)
	_check(not data.wolf_hunting[wolf.row], "paused frames do not commit completed results")
	engine.request_single_step()
	engine._process(0.0)
	_check(data.wolf_hunting[wolf.row] and data.memory_target[wolf.row] == sheep, "single step commits valid result at step start")

	_empty()
	sheep = entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(550, 300))[0]
	wolf = entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400, 300))[0]
	data.motion_facing[wolf.row] = Vector2.RIGHT
	job = _job(AnimalEntity.Kind.WOLF)
	engine.job_service.submit_async(job)
	_wait(job)
	entities.capture(sheep)
	entities.remove_expired(10.0)
	var replacement := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(550, 300))[0]
	_check(engine.animal_system.snapshot_animal(job.context, 0) == null, "reused slot rejects previous uid")
	engine.job_service.flush()
	_check(not data.wolf_hunting[wolf.row] and data.memory_target[wolf.row] != replacement, "dead prey result cannot target replacement after row swaps")
	var fresh := _job(AnimalEntity.Kind.WOLF)
	engine.job_service.submit_async(fresh)
	_wait(fresh)
	engine.job_service.flush()
	_check(data.memory_target[wolf.row] == replacement, "fresh snapshot resolves wolf current row after structural changes")
	job = _job(AnimalEntity.Kind.WOLF)
	engine.job_service.submit_async(job)
	_wait(job)
	engine.reset_simulation()
	engine.job_service.flush()
	_check(job.state == Job.State.DISCARDED and data.active_count == 0, "reset discards completed old-world result")

func _frequency_and_motion() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data := entities.data
	var wolf := entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400, 300))[0]
	var dog := entities.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(800, 500))[0]
	engine.config.wolf.decision_hz = 25
	engine.config.sheepdog.decision_hz = 15
	var counts := {&"Wolf": 0, &"Dog": 0}
	var sequences := {&"Wolf": -1, &"Dog": -1}
	for step in range(60):
		engine.simulate_step(1.0 / 60.0)
		for stage in engine.job_service.async_jobs:
			var job: Job = engine.job_service.async_jobs[stage]
			if sequences[stage] != job.context.sequence:
				counts[stage] += 1
				sequences[stage] = job.context.sequence
			_wait(job)
	_check(counts[&"Wolf"] == 25 and counts[&"Dog"] == 15, "non-divisor and independent frequencies preserve fractional time")
	engine.job_service.invalidate_async()
	var blocked := GateJob.new()
	blocked.stage = &"Wolf"
	engine.job_service.submit_async(blocked)
	blocked.entered.wait()
	var previous := data.motion_position[wolf.row]
	data.motion_intent[wolf.row] = AnimalData.MotionIntent.POINT
	data.motion_movement_goal[wolf.row] = Vector2(900, 300)
	data.motion_speed_limit[wolf.row] = 60.0
	for step in range(6):
		engine.simulate_step(1.0 / 60.0)
		_check(data.motion_position[wolf.row].distance_to(previous) > 0.0, "movement continues while selection is blocked")
		previous = data.motion_position[wolf.row]
	_check(engine.job_service.async_jobs[&"Wolf"] == blocked, "busy species does not accumulate requests")
	blocked.gate.post()
	_wait(blocked)
	engine.job_service.invalidate_async()
	data.brain_current_behavior[wolf.row] = AnimalEntity.Behavior.STALK
	data.wolf_strategy[wolf.row] = AnimalEntity.Strategy.SIDE
	data.memory_last_seen_position[wolf.row] = Vector2(600, 300)
	data.memory_last_seen_velocity[wolf.row] = Vector2.RIGHT
	data.motion_intent[wolf.row] = AnimalData.MotionIntent.POINT
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(600, 400))[0]
	data.brain_current_behavior[dog.row] = AnimalEntity.Behavior.COLLECT
	data.dog_collected_sheep[dog.row] = sheep
	data.dog_protection_center[dog.row] = Vector2(500, 400)
	data.motion_intent[dog.row] = AnimalData.MotionIntent.POINT
	engine.animal_system.update_steering(1.0 / 60.0)
	var goals := [data.motion_movement_goal[wolf.row], data.motion_movement_goal[dog.row]]
	for step in range(6):
		engine.animal_system.update_steering(1.0 / 60.0)
	_check(goals == [data.motion_movement_goal[wolf.row], data.motion_movement_goal[dog.row]], "stalk and collect offsets never accumulate between decisions")
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
	var settings := authored.copy_config()
	_check(settings.simulation_hz == 60.0 and settings.wolf.decision_hz == 30 and settings.sheepdog.decision_hz == 30, "old authored resources acquire clock and decision defaults")
	settings.simulation_hz = 15.0
	_check(not settings.validate().is_empty(), "decision frequency cannot exceed simulation rate")
	settings.simulation_hz = 90.0
	settings.wolf.decision_hz = 15
	settings.sheepdog.decision_hz = 25
	var blocked := GateJob.new()
	blocked.stage = &"Wolf"
	engine.job_service.invalidate_async()
	engine.job_service.submit_async(blocked)
	blocked.entered.wait()
	engine.request_config_apply(settings)
	var version: int = engine.job_service.async_version
	engine._process(0.0)
	_check(engine.job_service.async_version > version and engine.config.simulation_hz == 90.0, "hot configuration invalidates requests and applies clock")
	blocked.gate.post()
	_wait(blocked)
	engine.job_service.flush()
	_check(blocked.applications == 0 and blocked.state == Job.State.DISCARDED, "configuration change cannot commit an in-flight old request")
	var path := "res://output/async-decisions-20261116/test-preset.tres"
	_check(engine.save_preset(path) == OK, "frequency preset saves")
	var loaded: SimulationConfig = engine.load_preset(path)
	_check(loaded != null and loaded.simulation_hz == 90.0 and loaded.wolf.decision_hz == 15 and loaded.sheepdog.decision_hz == 25, "frequency preset round trips")
	scene.hud.parameters.set_draft(engine.config)
	_check(scene.hud.parameters.editors.has("World.simulation_hz") and scene.hud.parameters.editors.has("Wolves.decision_hz") and scene.hud.parameters.editors.has("Dogs.decision_hz"), "runtime panel exposes all frequencies")

func _timers_and_invalidation() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data := entities.data
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(550, 300))[0]
	var wolf := entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(400, 300))[0]
	var dog := entities.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(800, 500))[0]
	data.motion_facing[wolf.row] = Vector2.RIGHT
	engine.wolf_system.begin_hunt(wolf, sheep)
	engine.config.wolf.memory_duration = 0.0
	engine.wolf_system.advance_time(1.0 / 60.0)
	_check(data.wolf_hunting[wolf.row], "zero memory duration preserves currently visible prey")
	data.memory_target_visible[wolf.row] = 0
	engine.wolf_system.advance_time(1.0 / 60.0)
	_check(not data.wolf_hunting[wolf.row] and data.wolf_resting[wolf.row], "zero memory duration ends unseen hunt without waiting for worker")
	var elapsed := data.wolf_howl_elapsed[wolf.row]
	engine.wolf_system.advance_time(0.5)
	_check(is_equal_approx(data.wolf_howl_elapsed[wolf.row], elapsed + 0.5), "cooldown advances by simulation time independently of decisions")
	data.dog_protected_sheep[dog.row] = sheep
	data.dog_collected_sheep[dog.row] = sheep
	data.brain_current_behavior[dog.row] = AnimalEntity.Behavior.COLLECT
	entities.capture(sheep)
	entities.remove_expired()
	engine.dog_system.advance_time(1.0 / 60.0)
	_check(data.dog_protected_sheep[dog.row] == null and data.dog_collected_sheep[dog.row] == null and data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.PATROL, "lost dog anchor clears stale assignment and resumes patrol immediately")

func _run() -> void:
	_queues()
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	authored = engine.config.copy_config()
	_snapshots()
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
		var error := root.get_texture().get_image().save_png("res://output/async-decisions-20261116/running.png")
		_check(error == OK and engine.actual_simulation_hz > 0.0, "running scene renders HUD with measured simulation frequency")
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	print("ASYNC_DECISION_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
