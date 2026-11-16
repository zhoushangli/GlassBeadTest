class_name AnimalService
extends Service

var animal_system: AnimalSystem
var sheep_system: SheepSystem
var wolf_system: WolfSystem
var dog_system: SheepdogSystem

var update_elapsed: Dictionary = {}
var requested: Dictionary = {}
var applied: Dictionary = {}
var waiting: Dictionary = {}
var _last_decision: Dictionary = {}

var compute_backend: String = "auto"
var compute_fallback_reason: String = ""
var compute: SheepCompute
var preprocessing_samples: Array[Dictionary] = []
var _compute_waiting: bool = false

var actual_request_hz := Vector3.ZERO
var actual_apply_hz := Vector3.ZERO
var _window_requested := Vector3i.ZERO
var _window_applied := Vector3i.ZERO
var _window_started: int = 0

func _startup() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--compute="):
			compute_backend = argument.trim_prefix("--compute=")
	compute = SheepCompute.new()
	compute_fallback_reason = ""
	if compute_backend == "auto" and not compute.available():
		compute_fallback_reason = "RenderingDevice unavailable with %s / %s" % [DisplayServer.get_name(), RenderingServer.get_current_rendering_method()]
		print("COMPUTE_BACKEND cpu reason=" + compute_fallback_reason)
	var data: AnimalData = g_gameplayEngine.entity_service.data
	animal_system = AnimalSystem.new(data)
	sheep_system = SheepSystem.new(data)
	wolf_system = WolfSystem.new(data)
	dog_system = SheepdogSystem.new(data)
	_reset()

func _reset() -> void:
	preprocessing_samples.clear()
	_compute_waiting = false
	update_elapsed = {0: 0.0, 1: 0.0, 2: 0.0}
	requested = {0: 0, 1: 0, 2: 0}
	applied = {0: 0, 1: 0, 2: 0}
	waiting.clear()
	_last_decision.clear()
	actual_request_hz = Vector3.ZERO
	actual_apply_hz = Vector3.ZERO
	_window_requested = Vector3i.ZERO
	_window_applied = Vector3i.ZERO
	_window_started = Time.get_ticks_usec()

func _shutdown() -> void:
	if compute != null:
		compute.close()
		compute = null
	_reset()
	animal_system = null
	sheep_system = null
	wolf_system = null
	dog_system = null

func advance_decision(animal: AnimalEntity) -> void:
	var uid: int = g_gameplayEngine.entity_service.data.identity_uid[animal.row]
	var now: float = g_gameplayEngine.simulation_time
	animal_system.decide(animal, now - _last_decision.get(uid, now))
	_last_decision[uid] = now

func advance_time(delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var active_uids: Dictionary = {}
	for row in range(data.active_count):
		data.motion_wander_remaining[row] -= delta
		data.memory_perception_remaining[row] -= delta
		if data.identity_kind[row] == AnimalEntity.Kind.SHEEP:
			var duration: float = g_gameplayEngine.config.sheep.panic_duration
			data.sheep_panic_strength[row] = maxf(0.0, data.sheep_panic_strength[row] - delta / duration) if duration > 0.0 else 0.0
			if g_gameplayEngine.config.sheep.wander_weight > 0.0:
				animal_system.get_wander_point(data.handles[row], 85.0)
			continue

		var uid := data.identity_uid[row]
		active_uids[uid] = true
		data.memory_unseen_elapsed[row] += delta
		var target := data.live(data.memory_target[row])
		if target == null:
			data.memory_target[row] = null
			data.memory_target_visible[row] = 0
		if data.identity_kind[row] == AnimalEntity.Kind.SHEEPDOG and data.dog_collected_sheep[row] != null and data.live(data.dog_collected_sheep[row]) == null:
			data.dog_collected_sheep[row] = null
			data.motion_intent[row] = AnimalData.MotionIntent.STOP
			data.motion_desired_velocity[row] = Vector2.ZERO
		if not _last_decision.has(uid) or (target == null and data.brain_current_behavior[row] in [AnimalEntity.Behavior.CHASE, AnimalEntity.Behavior.STALK, AnimalEntity.Behavior.DRIVE]):
			advance_decision(data.handles[row])
	for uid in _last_decision.keys():
		if not active_uids.has(uid):
			_last_decision.erase(uid)
	wolf_system.advance_time(delta)
	dog_system.advance_time(delta)

func apply_completed() -> void:
	g_gameplayEngine.grid_service.reset_spatial_stats()
	g_gameplayEngine.job_service.flush()
	if compute != null:
		var output := compute.take_result()
		if not output.is_empty():
			_compute_waiting = false
			if output.snapshot.version == g_gameplayEngine.job_service.async_version:
				output.snapshot.gpu_complete = true
				output.snapshot.gpu_metrics = output.metrics
				apply_grid(output.grid, output.snapshot, output.sheep)
			else:
				output.sheep.state = Job.State.DISCARDED
				output.sheep.release_input()
		if _compute_waiting and not compute.failure.is_empty():
			compute_fallback_reason = compute.failure
			_compute_waiting = false
			waiting.clear()
	var now := Time.get_ticks_usec()
	var elapsed := (now - _window_started) / 1000000.0
	if elapsed >= 1.0:
		for kind in range(3):
			actual_request_hz[kind] = (requested[kind] - _window_requested[kind]) / elapsed
			actual_apply_hz[kind] = (applied[kind] - _window_applied[kind]) / elapsed
			_window_requested[kind] = requested[kind]
			_window_applied[kind] = applied[kind]
		_window_started = now

func schedule_updates(delta: float) -> void:
	if compute_backend == "gpu" and (compute == null or not compute.available()):
		return

	var engine := g_gameplayEngine
	var jobs: JobService = engine.job_service
	var rates := [engine.config.sheep_update_hz, engine.config.wolf_update_hz, engine.config.sheepdog_update_hz]
	var due := PackedInt32Array()
	for kind in range(3):
		var interval: float = 1.0 / rates[kind]
		update_elapsed[kind] += delta
		if waiting.has(kind) or jobs.async_jobs.has(stage_for(kind)):
			update_elapsed[kind] = minf(update_elapsed[kind], interval)
			continue
		if update_elapsed[kind] + 0.000000001 < interval:
			continue
		if jobs.async_jobs.has(&"Grid") or (compute != null and (compute.busy or _compute_waiting)):
			update_elapsed[kind] = minf(update_elapsed[kind], interval)
			continue

		var rows: PackedInt32Array = [engine.entity_service.sheep_rows, engine.entity_service.wolf_rows, engine.entity_service.dog_rows][kind]
		if rows.is_empty():
			update_elapsed[kind] = 0.0
			continue

		update_elapsed[kind] = maxf(0.0, update_elapsed[kind] - interval)
		due.append(kind)
		waiting[kind] = true
		requested[kind] += 1
	if due.is_empty():
		return

	# 1) Copy live inputs once; grid construction and species work use immutable snapshots.
	var prepared_at := Time.get_ticks_usec()
	var snapshot := animal_system.decision_snapshot(AnimalEntity.Kind.SHEEP)
	snapshot.due = due
	snapshot.config = {"cell_size": engine.config.grid_cell_size, "arena_size": engine.config.arena_size}
	snapshot.prepare_ms = (Time.get_ticks_usec() - prepared_at) / 1000.0
	snapshot.captured_usec = prepared_at
	snapshot.gpu = compute_backend != "cpu" and compute != null and compute.available()
	var job := GridAggregateJob.new()
	job.stage = &"Grid"
	job.context = snapshot
	job.target = self
	if not jobs.submit_async(job):
		for kind in due:
			waiting.erase(kind)

func apply_grid(grid: Dictionary, snapshot: Dictionary, sheep_job: SheepPerceptionJob = null) -> void:
	if snapshot.get("gpu", false) and not snapshot.get("gpu_complete", false):
		_compute_waiting = true
		compute.submit(grid, snapshot)
		return

	var engine := g_gameplayEngine
	engine.grid_service.install_snapshot(grid)
	for kind in snapshot.due:
		var context := snapshot.duplicate(false)
		context.erase("config")
		context.erase("due")
		context.grid = grid
		context.settings = snapshot.species_settings[kind]
		context.kind = kind
		context.rows = [snapshot.sheep, snapshot.wolves, snapshot.dogs][kind]
		context.cell_counts = grid.counts
		context.sheep_position_sums = grid.position_sums
		context.prepare_ms = snapshot.prepare_ms
		if kind == AnimalEntity.Kind.SHEEP and snapshot.get("gpu_complete", false):
			sheep_job.context = context
			apply_decision(sheep_job)
			sheep_job.state = Job.State.APPLIED
			sheep_job.release_input()
			waiting.erase(kind)
			continue

		var job: Job
		match kind:
			AnimalEntity.Kind.SHEEP:
				job = SheepPerceptionJob.new()
			AnimalEntity.Kind.WOLF:
				job = WolfPerceptionJob.new()
			_:
				job = DogPerceptionJob.new()
		job.stage = stage_for(kind)
		job.rows = context.rows
		job.context = context
		job.target = self
		engine.job_service.submit_async(job)
		waiting.erase(kind)

func apply_decision(job: Job) -> void:
	var snapshot := job.context
	var started_at := Time.get_ticks_usec()
	var kind: int = snapshot.kind
	match kind:
		AnimalEntity.Kind.SHEEP:
			sheep_system.apply_decision(job as SheepPerceptionJob)
		AnimalEntity.Kind.WOLF:
			wolf_system.apply_decision(job as WolfPerceptionJob)
		AnimalEntity.Kind.SHEEPDOG:
			dog_system.apply_decision(job as DogPerceptionJob)
	applied[kind] += 1
	if kind == AnimalEntity.Kind.SHEEP:
		var metrics: Dictionary = snapshot.get("gpu_metrics", {}).duplicate()
		metrics.backend = "gpu" if snapshot.get("gpu_complete", false) else "cpu"
		metrics.apply_ms = (Time.get_ticks_usec() - started_at) / 1000.0
		metrics.grid_ms = snapshot.get("grid_ms", 0.0)
		metrics.prepare_ms = snapshot.get("prepare_ms", 0.0)
		metrics.execute_ms = job.execute_ms
		metrics.latency_ms = (Time.get_ticks_usec() - snapshot.get("captured_usec", started_at)) / 1000.0
		metrics.processing_ms = metrics.prepare_ms + metrics.grid_ms + metrics.execute_ms + metrics.apply_ms + metrics.get("pack_ms", 0.0) + metrics.get("upload_submit_ms", 0.0) + maxf(0.0, metrics.get("gpu_ms", 0.0)) + metrics.get("decode_ms", 0.0)
		preprocessing_samples.append(metrics)
		if preprocessing_samples.size() > 4096:
			preprocessing_samples = preprocessing_samples.slice(2048)

func prepare_motion(_delta: float) -> void:
	wolf_system.prepare_motion_goals()
	dog_system.prepare_motion_goals()

func resolve_interactions(delta: float) -> void:
	for row in g_gameplayEngine.entity_service.wolf_rows:
		wolf_system.resolve_interactions(g_gameplayEngine.entity_service.data.handles[row], delta)

func stage_for(kind: int) -> StringName:
	return [&"Sheep", &"Wolf", &"Dog"][kind]
