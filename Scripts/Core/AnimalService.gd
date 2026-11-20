class_name AnimalService
extends Service

var animal_system: AnimalSystem
var sheep_system: SheepSystem
var wolf_system: WolfSystem
var dog_system: SheepdogSystem

var actual_request_hz := Vector3.ZERO
var actual_apply_hz := Vector3.ZERO
var _window_requested := Vector3i.ZERO
var _window_applied := Vector3i.ZERO
var _window_started: int = 0

func _startup() -> void:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	animal_system = AnimalSystem.new(data)
	sheep_system = SheepSystem.new(data)
	wolf_system = WolfSystem.new(data)
	dog_system = SheepdogSystem.new(data)
	_reset()

func _reset() -> void:
	refresh_config()
	g_gameplayEngine.profile_service.preprocessing_samples.clear()
	g_gameplayEngine.data_service.decisions.update_elapsed = {0: 0.0, 1: 0.0, 2: 0.0}
	g_gameplayEngine.data_service.decisions.requested = {0: 0, 1: 0, 2: 0}
	g_gameplayEngine.data_service.decisions.applied = {0: 0, 1: 0, 2: 0}
	g_gameplayEngine.data_service.decisions.waiting.clear()
	g_gameplayEngine.data_service.decisions.last_decision.clear()
	actual_request_hz = Vector3.ZERO
	actual_apply_hz = Vector3.ZERO
	_window_requested = Vector3i.ZERO
	_window_applied = Vector3i.ZERO
	_window_started = Time.get_ticks_usec()

func refresh_config() -> void:
	g_gameplayEngine.data_service.decisions.config = g_gameplayEngine.config.copy_config()

func _shutdown() -> void:
	_reset()
	animal_system = null
	sheep_system = null
	wolf_system = null
	dog_system = null

func advance_decision(animal: AnimalEntity) -> void:
	var id: int = g_gameplayEngine.data_service.animals.identity.animal_id[animal.row]
	var now: float = g_gameplayEngine.simulation_time
	animal_system.decide(animal, now - g_gameplayEngine.data_service.decisions.last_decision.get(id, now))
	g_gameplayEngine.data_service.decisions.last_decision[id] = now

func advance_time(delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	var animal_brain := data.brain
	var animal_identity := data.identity
	var animal_motion := data.motion
	var animal_memory := data.memory
	var animal_sheep := data.sheep
	var animal_dog := data.dog
	var animal_index := data.index
	var motion_wander_remaining := animal_motion.wander_remaining
	var memory_perception_remaining := animal_memory.perception_remaining
	var identity_kind := animal_identity.kind
	var sheep_panic_strength := animal_sheep.panic_strength
	var motion_position := animal_motion.position
	var motion_wander_point := animal_motion.wander_point
	var index_handles := animal_index.handles
	var identity_animal_id := animal_identity.animal_id
	var memory_unseen_elapsed := animal_memory.unseen_elapsed
	var memory_target := animal_memory.target
	var memory_target_visible := animal_memory.target_visible
	var dog_collected_sheep := animal_dog.collected_sheep
	var motion_intent := animal_motion.intent
	var motion_desired_velocity := animal_motion.desired_velocity
	var brain_current_behavior := animal_brain.current_behavior
	var profile: ProfileService = g_gameplayEngine.profile_service
	var detail_started := Time.get_ticks_usec() if profile.detailed_stats_enabled else 0

	# 1) Advance timers, renew wander goals and invalidate lost targets.
	var sheep_settings: SheepConfig = g_gameplayEngine.config.sheep
	var duration: float = sheep_settings.panic_duration
	var wander: bool = sheep_settings.wander_weight > 0.0
	var active_ids: Dictionary = {}
	for row in range(animal_index.active_count):
		motion_wander_remaining[row] -= delta
		memory_perception_remaining[row] -= delta

		if identity_kind[row] == AnimalEntity.Kind.SHEEP:
			sheep_panic_strength[row] = maxf(0.0, sheep_panic_strength[row] - delta / duration) if duration > 0.0 else 0.0
			if wander and (motion_wander_remaining[row] <= 0.0 or motion_position[row].distance_to(motion_wander_point[row]) < 15.0):
				animal_system.get_wander_point(index_handles[row], 85.0)
			continue

		var id := identity_animal_id[row]
		active_ids[id] = true
		memory_unseen_elapsed[row] += delta
		var target := data.live(memory_target[row])
		if target == null:
			memory_target[row] = null
			memory_target_visible[row] = 0

		if identity_kind[row] == AnimalEntity.Kind.SHEEPDOG and dog_collected_sheep[row] != null and data.live(dog_collected_sheep[row]) == null:
			dog_collected_sheep[row] = null
			motion_intent[row] = AnimalData.MotionIntent.STOP
			motion_desired_velocity[row] = Vector2.ZERO

		if not g_gameplayEngine.data_service.decisions.last_decision.has(id) or (target == null and brain_current_behavior[row] in [AnimalEntity.Behavior.CHASE, AnimalEntity.Behavior.STALK, AnimalEntity.Behavior.DRIVE]):
			advance_decision(index_handles[row])

	if profile.detailed_stats_enabled:
		profile.record_duration("AdvanceTime/ActiveLoop", (Time.get_ticks_usec() - detail_started) / 1000.0)
		detail_started = Time.get_ticks_usec()

	# 2) Remove obsolete decision timestamps before advancing species-specific timers.
	for id in g_gameplayEngine.data_service.decisions.last_decision.keys():
		if not active_ids.has(id):
			g_gameplayEngine.data_service.decisions.last_decision.erase(id)
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
			actual_request_hz[kind] = (g_gameplayEngine.data_service.decisions.requested[kind] - _window_requested[kind]) / elapsed
			actual_apply_hz[kind] = (g_gameplayEngine.data_service.decisions.applied[kind] - _window_applied[kind]) / elapsed
			_window_requested[kind] = g_gameplayEngine.data_service.decisions.requested[kind]
			_window_applied[kind] = g_gameplayEngine.data_service.decisions.applied[kind]
		_window_started = now

func schedule_updates(delta: float) -> void:
	var engine := g_gameplayEngine
	var compute: ComputeShaderService = engine.compute_service
	if not compute.available():
		engine.fail_step("GPU compute unavailable: " + compute.failure)
		return

	# 1) Select due species without queuing catch-up work behind an unfinished batch.
	var jobs: JobService = engine.job_service
	var rates := [engine.config.sheep_update_hz, engine.config.wolf_update_hz, engine.config.sheepdog_update_hz]
	var due := PackedInt32Array()
	for kind in range(3):
		var interval: float = 1.0 / rates[kind]
		g_gameplayEngine.data_service.decisions.update_elapsed[kind] += delta
		if g_gameplayEngine.data_service.decisions.waiting.has(kind) or jobs.async_jobs.has(stage_for(kind)):
			g_gameplayEngine.data_service.decisions.update_elapsed[kind] = minf(g_gameplayEngine.data_service.decisions.update_elapsed[kind], interval)
			continue
		if g_gameplayEngine.data_service.decisions.update_elapsed[kind] + 0.000000001 < interval:
			continue
		if jobs.async_jobs.has(&"Grid") or compute.busy:
			g_gameplayEngine.data_service.decisions.update_elapsed[kind] = minf(g_gameplayEngine.data_service.decisions.update_elapsed[kind], interval)
			continue

		var rows: PackedInt32Array = [engine.data_service.animals.index.sheep_rows, engine.data_service.animals.index.wolf_rows, engine.data_service.animals.index.dog_rows][kind]
		if rows.is_empty():
			g_gameplayEngine.data_service.decisions.update_elapsed[kind] = 0.0
			continue

		g_gameplayEngine.data_service.decisions.update_elapsed[kind] = maxf(0.0, g_gameplayEngine.data_service.decisions.update_elapsed[kind] - interval)
		due.append(kind)
		g_gameplayEngine.data_service.decisions.waiting[kind] = true
		g_gameplayEngine.data_service.decisions.requested[kind] += 1

	if due.is_empty():
		return

	# 2) Copy live inputs once; grid construction and species work use immutable snapshots.
	var job: GridAggregateJob = GridAggregateJob.new()
	job.stage = &"Grid"
	job.capture(due)
	engine.profile_service.record_duration("Snapshot/Prepare", job.snapshot.prepare_ms)
	if not jobs.submit_async(job):
		for kind in due:
			g_gameplayEngine.data_service.decisions.waiting.erase(kind)

func prepare_motion(_delta: float) -> void:
	wolf_system.prepare_motion_goals()
	dog_system.prepare_motion_goals()

func resolve_interactions(delta: float) -> void:
	for row in g_gameplayEngine.data_service.animals.index.wolf_rows:
		wolf_system.resolve_interactions(g_gameplayEngine.data_service.animals.index.handles[row], delta)

func stage_for(kind: int) -> StringName:
	return [&"Sheep", &"Wolf", &"Dog"][kind]
