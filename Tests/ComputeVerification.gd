extends SceneTree

const ReferenceSimulation = preload("res://Tests/ReferenceSimulation.gd")

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node
var compute: ComputeShaderService
var max_error: float = 0.0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _near(actual: float, expected: float, label: String) -> void:
	max_error = maxf(max_error, absf(actual - expected))
	_check(is_finite(actual) and absf(actual - expected) <= 0.001 + absf(expected) * 0.0001, label)

func _vector(actual: Vector2, expected: Vector2, label: String) -> void:
	_near(actual.x, expected.x, label + ".x")
	_near(actual.y, expected.y, label + ".y")

func _receive(snapshot: AnimalSnapshot) -> SheepComputeJob:
	var job: SheepComputeJob = SheepComputeJob.new()
	job.snapshot = snapshot
	job.grid = GridAggregateJob.build_snapshot(snapshot)
	_check(compute.submit(job), "GPU service accepts immutable input")
	var deadline := Time.get_ticks_msec() + 10000
	var result: SheepComputeJob
	while result == null and Time.get_ticks_msec() < deadline:
		result = compute._take_completed()
		if result == null:
			await process_frame
	_check(result != null and job.error.is_empty() and not job.is_cancelled(), "GPU finishes without blocking main thread")
	_check(job.task_id == -1 and compute.owner_thread_id != OS.get_thread_caller_id(), "GPU uses its own device thread without a pool task")
	_check(job.metrics.gpu_ms >= 0.0, "local device returns GPU timestamps")
	return job

func _snapshot() -> AnimalSnapshot:
	var snapshot: AnimalSnapshot = GridAggregateJob.capture_snapshot()
	snapshot.config = engine.config.copy_config()
	snapshot.due = PackedInt32Array([0])
	snapshot.captured_usec = Time.get_ticks_usec()
	return snapshot

func _compare(snapshot: AnimalSnapshot, label: String) -> void:
	var grid := ReferenceSimulation.build_snapshot(snapshot)
	var expected: ReferenceSimulation.SheepJob = ReferenceSimulation.SheepJob.new()
	expected.rows = snapshot.index.sheep_rows if snapshot.due.has(0) else PackedInt32Array()
	expected.snapshot = snapshot
	expected.grid = grid
	ReferenceSimulation.calculate_snapshot(expected)
	var result := await _receive(snapshot)
	if not result.error.is_empty():
		_check(false, label + " returns a result")
		return

	for cell in grid.cells.occupied:
		_check(result.grid.flock.counts[cell] == grid.flock.counts[cell], label + " flock count")
		_check(result.grid.flock.alignment_counts[cell] == grid.flock.alignment_counts[cell], label + " alignment count")
		_vector(result.grid.flock.sums[cell], grid.flock.sums[cell], label + " flock sum")
		_vector(result.grid.flock.alignment_sums[cell], grid.flock.alignment_sums[cell], label + " alignment sum")
	_check(result.rows == expected.rows, label + " entry count")
	_check(result.pressure_source_pairs == expected.pressure_source_pairs, label + " source pairs")
	var actual: SheepPerceptionJob = result
	for index in range(expected.rows.size()):
		_check(actual.neighbor_counts[index] == expected.neighbor_counts[index] and actual.refresh_flags[index] == expected.refresh_flags[index], label + " count and refresh")
		for field in ["separations", "centers", "alignments", "threat_directions", "dog_pressures", "desired_velocities"]:
			_vector(actual.get(field)[index], expected.get(field)[index], label + " " + field)
		for field in ["threat_strengths", "speed_limits"]:
			_near(actual.get(field)[index], expected.get(field)[index], label + " " + field)
	for node in grid.pressure.nodes:
		_vector(result.wolf_pressure[node], expected.wolf_pressure[node], label + " wolf field")
		_vector(result.dog_pressure[node], expected.dog_pressure[node], label + " dog field")

func _reset() -> void:
	engine.reset_simulation()
	engine.paused = true

func _run() -> void:
	for shader_file in [ComputeShaderService.SHEEP_SHADER, ComputeShaderService.MOVEMENT_SHADER]:
		var spirv: RDShaderSPIRV = shader_file.get_spirv()
		_check(spirv != null and not spirv.bytecode_compute.is_empty() and spirv.compile_error_compute.is_empty(), "imported shader contains valid compute bytecode")

	scene = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	var settings: SimulationConfig = scene.simulation_config.copy_config()
	settings.initial_total = 0
	settings.arena_size = Vector2(1280, 720)
	scene.simulation_config = settings
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.paused = true
	engine.set_process(false)
	compute = ComputeShaderService.new()
	root.add_child(compute)
	compute.startup()
	_check(compute.available(), "Forward+ compute available")
	await _compare(_snapshot(), "empty")
	engine.entity_service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(200, 200))
	await _compare(_snapshot(), "single")
	engine.entity_service.spawn(AnimalEntity.Kind.SHEEP, 12, Vector2(200, 200))
	engine.entity_service.spawn(AnimalEntity.Kind.WOLF, 2, Vector2(200, 200))
	engine.entity_service.spawn(AnimalEntity.Kind.SHEEPDOG, 2, Vector2(220, 200))
	await _compare(_snapshot(), "overlap and shared pressure")
	var snapshot := _snapshot()
	snapshot.distance = 0.0
	snapshot.config.sheep.wolf_pressure_distance = 0.0
	snapshot.config.sheep.herding_distance = 0.0
	await _compare(snapshot, "zero radii")
	_reset()
	var sheep: Array[AnimalEntity] = engine.entity_service.spawn(AnimalEntity.Kind.SHEEP, 96)
	engine.entity_service.spawn(AnimalEntity.Kind.WOLF, 12)
	engine.entity_service.spawn(AnimalEntity.Kind.SHEEPDOG, 6)
	var data: AnimalData = engine.data_service.animals
	for animal in sheep:
		var row: int = animal.row
		data.motion.velocity[row] = Vector2(row * 0.5, -row * 0.2)
		data.sheep.panic_strength[row] = 0.4 if row % 3 == 0 else 0.0
		data.sheep.panic_source[row] = Vector2(400, 400)
		data.memory.perception_ready[row] = int(row % 2 == 0)
		data.memory.perception_remaining[row] = 0.1 if row % 2 == 0 else 0.0
	for row in engine.data_service.animals.index.wolf_rows:
		data.wolf.hunting[row] = int(row % 2 == 0)
	await _compare(_snapshot(), "mixed velocities panic and cached perception")
	await _compare(GridAggregateJob.capture_snapshot(PackedInt32Array([1])), "pressure without sheep decisions")
	_reset()
	for point in [Vector2(12, 94), Vector2(1268, 662), Vector2(100, 200), Vector2(230, 200), Vector2(230.01, 200), Vector2(229.99, 200)]:
		engine.entity_service.spawn(AnimalEntity.Kind.SHEEP, 1, point)
	engine.entity_service.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(100, 200))
	engine.entity_service.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(140, 200))
	await _compare(_snapshot(), "arena and influence boundaries")
	await _lifecycle()
	compute.shutdown()
	compute.queue_free()
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	print("COMPUTE_VERIFICATION checks=%d failures=%d max_absolute_error=%.8f" % [checks, failures, max_error])
	quit(1 if failures else 0)

func _lifecycle() -> void:
	engine.job_service.max_workers = 1
	var snapshot := _snapshot()
	var output := await _receive(snapshot)
	var data: AnimalData = engine.data_service.animals
	var sheep: AnimalEntity = data.index.handles[engine.data_service.animals.index.sheep_rows[0]]
	engine.entity_service.capture(sheep)
	engine.entity_service.remove_expired(10.0)
	var replacement: AnimalEntity = engine.entity_service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(600, 400))[0]
	data.motion.desired_velocity[replacement.row] = Vector2(7, 9)
	output.snapshot = snapshot
	output.apply_result()
	_check(data.motion.desired_velocity[replacement.row] == Vector2(7, 9), "old GPU result cannot change reused slot")
	var panic_snapshot := _snapshot()
	var panic_output := await _receive(panic_snapshot)
	engine.sheep_system.receive_howl(replacement, Vector2(20, 20))
	data.motion.desired_velocity[replacement.row] = Vector2(11, 13)
	panic_output.snapshot = panic_snapshot
	panic_output.apply_result()
	_check(data.motion.desired_velocity[replacement.row] == Vector2(11, 13), "new panic rejects old GPU steering")
	engine.compute_service.shutdown()
	engine.compute_service.startup()
	engine.animal_service.schedule_updates(1.0)
	var deadline := Time.get_ticks_msec() + 10000
	while not engine.compute_service.busy and Time.get_ticks_msec() < deadline:
		engine.animal_service.apply_completed()
		await process_frame
	_check(engine.compute_service.busy, "integrated GPU request in flight")
	engine.reset_simulation()
	engine.paused = true
	for index in range(12):
		await process_frame
	engine.animal_service.apply_completed()
	_check(engine.data_service.decisions.applied[0] == 0, "reset discards GPU result by request version")
	deadline = Time.get_ticks_msec() + 10000
	while engine.compute_service.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not engine.compute_service.busy, "reset retires the cancelled device request while paused")
	engine.entity_service.spawn(AnimalEntity.Kind.SHEEP, 8, Vector2(300, 300))
	engine.animal_service.schedule_updates(1.0)
	deadline = Time.get_ticks_msec() + 10000
	while engine.data_service.decisions.applied[0] == 0 and Time.get_ticks_msec() < deadline:
		engine.animal_service.apply_completed()
		await process_frame
	_check(engine.data_service.decisions.applied[0] > 0, "GPU resumes after reset")
	engine.animal_service.schedule_updates(1.0)
	for index in range(12):
		engine.animal_service.apply_completed()
		await process_frame
	var before := int(engine.data_service.decisions.applied[0])
	engine.animal_service.schedule_updates(1.0)
	engine.job_service.invalidate_async()
	for index in range(12):
		await process_frame
	engine.animal_service.apply_completed()
	_check(engine.data_service.decisions.applied[0] == before, "configuration version invalidates pending work")
	engine.animal_service.schedule_updates(1.0)
	engine.stop_simulation()
	for index in range(12):
		await process_frame
	_check(not engine.running, "stop safely retires GPU work")
