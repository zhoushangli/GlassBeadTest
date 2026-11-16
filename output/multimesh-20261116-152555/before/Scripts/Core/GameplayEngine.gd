extends Node

signal simulation_stepped
signal configuration_applied(restarted: bool)

const PRESET_PATH := "user://CFG_Runtime.tres"

@export var config: SimulationConfig
@export_range(1, 16, 1) var max_steps_per_frame: int = 4

@onready var job_service: JobService = $JobService
@onready var grid_service: GridService = $GridService
@onready var entity_service: EntityService = $EntityService
@onready var debug_service: DebugService = $DebugService
@onready var profile_service: ProfileService = $ProfileService

var defaults: SimulationConfig
var rng := RandomNumberGenerator.new()
var running: bool = false
var paused: bool = false:
	set(value):
		if paused != value:
			_accumulator = 0.0
			_step_pending = false
			reset_frequency_window()
		paused = value

var simulation_time: float = 0.0
var step_count: int = 0

var _pending_spawns: Array[Vector2i] = []
var _pending_config: SimulationConfig
var _reset_pending: bool = false
var _step_pending: bool = false
var _accumulator: float = 0.0
var _clock_error_reported: bool = false

var actual_simulation_hz: float = 0.0
var _frequency_started: int = 0
var _frequency_steps: int = 0
var _decision_elapsed: Dictionary = {AnimalEntity.Kind.WOLF: 0.0, AnimalEntity.Kind.SHEEPDOG: 0.0}
var _last_decision: Dictionary = {}

var animal_system: AnimalSystem
var sheep_system: SheepSystem
var wolf_system: WolfSystem
var dog_system: SheepdogSystem

func start_simulation(world: Node2D, debug_hud: DebugHUD, settings: SimulationConfig) -> void:
	stop_simulation()
	var error := settings.validate()
	if not error.is_empty():
		push_error(error)
		return

	defaults = settings.copy_config()
	config = settings.copy_config()
	entity_service.container = world.get_node("Animals")
	debug_service.hud = debug_hud
	_create_systems()
	running = true
	job_service.startup()
	grid_service.startup()
	entity_service.startup()
	profile_service.startup()
	debug_service.startup()
	reset_simulation()

func stop_simulation() -> void:
	running = false
	job_service.shutdown()
	debug_service.shutdown()
	profile_service.shutdown()
	entity_service.shutdown()
	grid_service.shutdown()
	_pending_spawns.clear()
	_pending_config = null
	_reset_pending = false
	_step_pending = false
	_accumulator = 0.0

func reset_simulation() -> void:
	job_service.reset()
	debug_service.reset()
	entity_service.reset()
	profile_service.reset()
	_accumulator = 0.0
	_clock_error_reported = false
	_pending_spawns.clear()
	_reset_pending = false
	_step_pending = false
	rng.seed = config.random_seed
	simulation_time = 0.0
	step_count = 0
	_reset_decisions()
	reset_frequency_window()
	paused = false
	entity_service.spawn_initial()

func request_config_apply(settings: SimulationConfig) -> String:
	var error := settings.validate()
	if not error.is_empty():
		return error
	_pending_config = settings.copy_config()
	return ""

func _apply_pending_config() -> void:
	var restart := _pending_config.requires_restart(config)
	var was_paused := paused
	config = _pending_config
	_pending_config = null
	job_service.invalidate_async()
	_reset_decisions()
	_accumulator = 0.0
	reset_frequency_window()
	if restart:
		reset_simulation()
		paused = was_paused
	else:
		for animal in entity_service.entities:
			g_gameplayEngine.refresh_animal_config(animal)
	configuration_applied.emit(restart)

func save_preset(path: String = PRESET_PATH) -> Error:
	var preset := config.copy_config()
	preset.preset_version = SimulationConfig.PRESET_VERSION
	return ResourceSaver.save(preset, path)

func load_preset(path: String = PRESET_PATH) -> SimulationConfig:
	if not FileAccess.file_exists(path):
		return null

	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SimulationConfig
	if loaded == null or loaded.preset_version != SimulationConfig.PRESET_VERSION or not loaded.validate().is_empty():
		return null
	return loaded.copy_config()

func request_spawn(kind: AnimalEntity.Kind, count: int) -> void:
	_pending_spawns.append(Vector2i(kind, count))

func request_reset() -> void:
	_reset_pending = true

func request_single_step() -> void:
	if paused:
		_step_pending = true

func random_position() -> Vector2:
	return Vector2(rng.randf_range(24.0, config.arena_size.x - 24.0),
		rng.randf_range(100.0, config.arena_size.y - 65.0))

func _process(delta: float) -> void:
	if not running:
		return
	update_frequency()

	# 1) Apply UI commands before iterating entities, including while paused.
	if _pending_config != null:
		_apply_pending_config()
	if _reset_pending:
		reset_simulation()
	for request in _pending_spawns:
		entity_service.spawn(request.x, request.y)
	_pending_spawns.clear()

	var interval := 1.0 / config.simulation_hz if is_finite(config.simulation_hz) and config.simulation_hz > 0.0 else 0.0
	if not is_finite(interval) or interval <= 0.0 or max_steps_per_frame <= 0 or not is_finite(delta) or delta < 0.0:
		_accumulator = 0.0
		_step_pending = false
		if not _clock_error_reported:
			push_error("Simulation interval and step limit must be finite and positive; frame delta must be finite and nonnegative.")
		_clock_error_reported = true
		return

	_clock_error_reported = false
	if paused:
		_accumulator = 0.0
		if _step_pending:
			_step_pending = false
			simulate_step(interval)
		return

	# 2) Calculate a bounded step count and retain only the fractional remainder.
	_accumulator += delta
	var pending_steps := floorf(_accumulator / interval + 0.000000001)
	var steps := int(minf(pending_steps, float(max_steps_per_frame)))
	_accumulator = maxf(0.0, _accumulator - pending_steps * interval)
	for index in range(steps):
		simulate_step(interval)

func simulate_step(delta: float) -> void:
	profile_service.begin_step()
	entity_service.remove_expired()

	# 1) Commit completed decisions without waiting, then advance simulation timers.
	job_service.flush()
	profile_service.end_stage("Decision")
	_advance_decision_time(delta)

	# 2) Build spatial input for sheep perception and new asynchronous requests.
	grid_service.rebuild()
	dog_system.begin_spatial_step()
	profile_service.end_stage("SpatialBuild")

	wolf_system.accumulate_sheep_pressure()
	dog_system.accumulate_sheep_pressure()
	sheep_system.perceive_batch(delta)
	_submit_decisions(delta)
	profile_service.end_stage("Perception")

	profile_service.end_stage("TaskAssignment")

	# 3) Steer and move every animal using the latest valid intent.
	animal_system.update_steering(delta)
	profile_service.end_stage("Steering")
	animal_system.update_movement(delta)
	profile_service.end_stage("Movement")

	# 4) Resolve howls and captures at the resulting positions.
	for row in entity_service.wolf_rows:
		wolf_system.resolve_interactions(entity_service.data.handles[row], delta)
	profile_service.end_stage("Interaction")

	entity_service.remove_expired(delta)
	for row in range(entity_service.data.active_count):
		entity_service.data.brain_view[row].sync()
	debug_service.advance_visuals(delta)
	simulation_time += delta
	step_count += 1
	_frequency_steps += 1
	profile_service.end_step()
	simulation_stepped.emit()

func reset_frequency_window() -> void:
	actual_simulation_hz = 0.0
	_frequency_started = Time.get_ticks_usec()
	_frequency_steps = 0

func update_frequency() -> void:
	var now := Time.get_ticks_usec()
	var elapsed := now - _frequency_started
	if elapsed >= 1000000:
		actual_simulation_hz = _frequency_steps * 1000000.0 / elapsed if not paused else 0.0
		_frequency_steps = 0
		_frequency_started = now

func _reset_decisions() -> void:
	_decision_elapsed = {AnimalEntity.Kind.WOLF: 0.0, AnimalEntity.Kind.SHEEPDOG: 0.0}
	_last_decision.clear()

func advance_decision(animal: AnimalEntity) -> void:
	var uid: int = entity_service.data.identity_uid[animal.row]
	var elapsed: float = simulation_time - _last_decision.get(uid, simulation_time)
	animal_system.decide(animal, elapsed)
	_last_decision[uid] = simulation_time

func _advance_decision_time(delta: float) -> void:
	var data := entity_service.data
	var active_uids: Dictionary = {}
	for row in range(data.active_count):
		if data.identity_kind[row] == AnimalEntity.Kind.SHEEP:
			continue

		var uid := data.identity_uid[row]
		active_uids[uid] = true
		data.motion_wander_remaining[row] -= delta
		data.memory_perception_remaining[row] -= delta
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

func _submit_decisions(delta: float) -> void:
	for kind in [AnimalEntity.Kind.WOLF, AnimalEntity.Kind.SHEEPDOG]:
		var stage: StringName = &"Wolf" if kind == AnimalEntity.Kind.WOLF else &"Dog"
		var settings: Resource = config.wolf if kind == AnimalEntity.Kind.WOLF else config.sheepdog
		var interval := 1.0 / float(settings.decision_hz)
		_decision_elapsed[kind] += delta
		if job_service.async_jobs.has(stage):
			_decision_elapsed[kind] = minf(_decision_elapsed[kind], interval)
			continue
		if _decision_elapsed[kind] + 0.000000001 < interval:
			continue

		var rows: PackedInt32Array = entity_service.wolf_rows if kind == AnimalEntity.Kind.WOLF else entity_service.dog_rows
		if rows.is_empty():
			continue

		var job: Job = WolfPerceptionJob.new() if kind == AnimalEntity.Kind.WOLF else DogPerceptionJob.new()
		job.stage = stage
		var prepared_at := Time.get_ticks_usec()
		job.context = animal_system.decision_snapshot(kind)
		job.context.prepare_ms = (Time.get_ticks_usec() - prepared_at) / 1000.0
		job.rows = job.context.rows
		job.target = wolf_system if kind == AnimalEntity.Kind.WOLF else dog_system
		if job_service.submit_async(job):
			_decision_elapsed[kind] = maxf(0.0, _decision_elapsed[kind] - interval)

func _create_systems() -> void:
	animal_system = AnimalSystem.new(entity_service.data)
	sheep_system = SheepSystem.new(entity_service.data)
	wolf_system = WolfSystem.new(entity_service.data)
	dog_system = SheepdogSystem.new(entity_service.data)

func refresh_animal_config(animal: AnimalEntity) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	data.settings[row] = [config.sheep, config.wolf, config.sheepdog][data.identity_kind[row]]
	data.memory_perception_ready[row] = false
	if data.identity_kind[row] == AnimalEntity.Kind.SHEEP and config.sheep.panic_duration == 0.0:
		data.sheep_panic_strength[row] = 0.0
	if data.identity_kind[row] != AnimalEntity.Kind.SHEEP:
		data.memory_vision_radius_squared[row] = data.settings[row].perception_radius * data.settings[row].perception_radius
		data.memory_vision_cos[row] = cos(deg_to_rad(data.settings[row].vision_angle * 0.5))
	if data.identity_kind[row] == AnimalEntity.Kind.SHEEPDOG:
		data.dog_assignment_remaining[row] = 0.0

func debug_details(animal: AnimalEntity) -> String:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var system: RefCounted = [sheep_system, wolf_system, dog_system][data.identity_kind[row]]
	return system.call("get_debug_details", animal)
