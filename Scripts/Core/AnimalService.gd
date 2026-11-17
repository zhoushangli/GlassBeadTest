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

var preprocessing_samples: Array[ComputeShaderService.Metrics] = []
var snapshot_config: SimulationConfig

var actual_request_hz := Vector3.ZERO
var actual_apply_hz := Vector3.ZERO
var _window_requested := Vector3i.ZERO
var _window_applied := Vector3i.ZERO
var _window_started: int = 0

func _startup() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	animal_system = AnimalSystem.new(data)
	sheep_system = SheepSystem.new(data)
	wolf_system = WolfSystem.new(data)
	dog_system = SheepdogSystem.new(data)
	_reset()

func _reset() -> void:
	refresh_config()
	preprocessing_samples.clear()
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

func refresh_config() -> void:
	snapshot_config = g_gameplayEngine.config.copy_config()

func _shutdown() -> void:
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
	var profile: ProfileService = g_gameplayEngine.profile_service
	var detail_started := Time.get_ticks_usec() if profile.detailed_stats_enabled else 0
	var numeric: int = g_gameplayEngine.compute_service.run_numeric(data, delta, NumericComputeJob.Pass.TIMERS)
	if numeric < 0:
		g_gameplayEngine.fail_step("GPU timers failed")
		return

	var sheep_settings: SheepConfig = g_gameplayEngine.config.sheep
	var duration: float = sheep_settings.panic_duration
	var wander: bool = sheep_settings.wander_weight > 0.0
	var active_uids: Dictionary = {}
	for row in range(data.active_count):
		if numeric == 0:
			data.motion_wander_remaining[row] -= delta
			data.memory_perception_remaining[row] -= delta
		if data.identity_kind[row] == AnimalEntity.Kind.SHEEP:
			if numeric == 0:
				data.sheep_panic_strength[row] = maxf(0.0, data.sheep_panic_strength[row] - delta / duration) if duration > 0.0 else 0.0
			if wander and (data.motion_wander_remaining[row] <= 0.0 or data.motion_position[row].distance_to(data.motion_wander_point[row]) < 15.0):
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
	if profile.detailed_stats_enabled:
		profile.record_duration("AdvanceTime/ActiveLoop", (Time.get_ticks_usec() - detail_started) / 1000.0)
		detail_started = Time.get_ticks_usec()

	for uid in _last_decision.keys():
		if not active_uids.has(uid):
			_last_decision.erase(uid)
	if profile.detailed_stats_enabled:
		profile.record_duration("AdvanceTime/DecisionHistory", (Time.get_ticks_usec() - detail_started) / 1000.0)
		detail_started = Time.get_ticks_usec()

	wolf_system.advance_time(delta)
	if profile.detailed_stats_enabled:
		profile.record_duration("AdvanceTime/WolfTimers", (Time.get_ticks_usec() - detail_started) / 1000.0)
		detail_started = Time.get_ticks_usec()

	dog_system.advance_time(delta)
	if profile.detailed_stats_enabled:
		profile.record_duration("AdvanceTime/DogTimers", (Time.get_ticks_usec() - detail_started) / 1000.0)

func apply_completed() -> void:
	g_gameplayEngine.grid_service.reset_spatial_stats()
	g_gameplayEngine.job_service.flush()
	g_gameplayEngine.compute_service.flush()
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
	var engine := g_gameplayEngine
	var compute: ComputeShaderService = engine.compute_service
	if compute.backend == "gpu" and not compute.available():
		return
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
		if jobs.async_jobs.has(&"Grid") or compute.busy:
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
	var gpu := compute.available()
	var snapshot := animal_system.decision_snapshot(due, gpu)
	snapshot.prepare_ms = (Time.get_ticks_usec() - prepared_at) / 1000.0
	engine.profile_service.record_duration("Snapshot/Prepare", snapshot.prepare_ms)
	snapshot.captured_usec = prepared_at
	var job := GridAggregateJob.new()
	job.stage = &"Grid"
	job.snapshot = snapshot
	job.target = self
	if not jobs.submit_async(job):
		for kind in due:
			waiting.erase(kind)

func apply_grid(grid: GridSnapshot, snapshot: AnimalSnapshot, sheep_job: SheepComputeJob = null, grid_ms: float = 0.0) -> void:
	var engine := g_gameplayEngine
	if snapshot.gpu and sheep_job == null:
		var job := SheepComputeJob.new()
		job.stage = &"Compute"
		job.snapshot = snapshot
		job.grid = grid
		job.grid_ms = grid_ms
		job.target = self
		if not engine.compute_service.submit(job):
			for kind in snapshot.due:
				waiting.erase(kind)
			job.release_input()
		return

	engine.grid_service.install_snapshot(grid)
	for kind in snapshot.due:
		if kind == AnimalEntity.Kind.SHEEP and sheep_job != null:
			apply_decision(sheep_job)
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
		job.rows = snapshot.rows_for(kind)
		job.snapshot = snapshot
		job.grid = grid
		job.grid_ms = grid_ms
		job.target = self
		engine.job_service.submit_async(job)
		waiting.erase(kind)

func compute_failed(message: String, snapshot: AnimalSnapshot) -> void:
	g_gameplayEngine.compute_service.fallback_reason = message
	for kind in snapshot.due:
		waiting.erase(kind)
	push_warning("ComputeShaderService: " + message)

func apply_decision(job: Job) -> void:
	var snapshot := job.snapshot
	var started_at := Time.get_ticks_usec()
	var kind: int = AnimalEntity.Kind.SHEEP if job is SheepPerceptionJob else (AnimalEntity.Kind.WOLF if job is WolfPerceptionJob else AnimalEntity.Kind.SHEEPDOG)
	match kind:
		AnimalEntity.Kind.SHEEP:
			sheep_system.apply_decision(job as SheepPerceptionJob)
		AnimalEntity.Kind.WOLF:
			wolf_system.apply_decision(job as WolfPerceptionJob)
		AnimalEntity.Kind.SHEEPDOG:
			dog_system.apply_decision(job as DogPerceptionJob)
	var apply_ms := (Time.get_ticks_usec() - started_at) / 1000.0
	var profile: ProfileService = g_gameplayEngine.profile_service
	profile.record_duration("Species/" + String(stage_for(kind)) + "/Apply", apply_ms)
	applied[kind] += 1
	if kind == AnimalEntity.Kind.SHEEP:
		var metrics := (job as SheepComputeJob).metrics if job is SheepComputeJob else ComputeShaderService.Metrics.new()
		metrics.backend = "gpu" if job is SheepComputeJob else "cpu"
		metrics.apply_ms = apply_ms
		metrics.grid_ms = job.grid_ms
		metrics.prepare_ms = snapshot.prepare_ms
		metrics.execute_ms = job.execute_ms
		metrics.latency_ms = (Time.get_ticks_usec() - snapshot.captured_usec) / 1000.0
		var cpu_ms := metrics.pack_ms + metrics.decode_ms if job is SheepComputeJob else job.execute_ms
		metrics.processing_ms = metrics.prepare_ms + metrics.grid_ms + cpu_ms + metrics.apply_ms + metrics.upload_submit_ms + maxf(0.0, metrics.gpu_ms) + maxf(0.0, metrics.buffer_read_ms)
		if job is SheepComputeJob:
			for metric in ["pack_ms", "device_queue_ms", "upload_submit_ms", "gpu_wait_ms", "buffer_read_ms", "decode_ms"]:
				profile.record_duration("Compute/" + metric, metrics.get(metric))
			profile.record_duration("Compute/GPU", metrics.gpu_ms)
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
