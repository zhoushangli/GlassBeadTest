extends Node

signal simulation_frame_completed(elapsed_ms: float)
signal simulation_stepped
signal configuration_applied(restarted: bool)

const PRESET_PATH := "user://CFG_Runtime.tres"

@export var config: SimulationConfig

@onready var compute_service: ComputeShaderService = $ComputeShaderService
@onready var animal_service: AnimalService = $AnimalService
@onready var job_service: JobService = $JobService
@onready var grid_service: GridService = $GridService
@onready var entity_service: EntityService = $EntityService
@onready var render_service: RenderService = $RenderService
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
var step_failed: bool = false

var _pending_spawns: Array[Vector2i] = []
var _pending_config: SimulationConfig
var _reset_pending: bool = false
var _step_pending: bool = false
var _accumulator: float = 0.0
var _clock_error_reported: bool = false

var actual_simulation_hz: float = 0.0
var _frequency_started: int = 0
var _frequency_steps: int = 0

var animal_system: AnimalSystem:
	get:
		return animal_service.animal_system
var sheep_system: SheepSystem:
	get:
		return animal_service.sheep_system
var wolf_system: WolfSystem:
	get:
		return animal_service.wolf_system
var dog_system: SheepdogSystem:
	get:
		return animal_service.dog_system

func start_simulation(world: Node2D, debug_hud: DebugHUD, settings: SimulationConfig) -> void:
	stop_simulation()
	var error := settings.validate()
	if not error.is_empty():
		push_error(error)
		return

	defaults = settings.copy_config()
	config = settings.copy_config()
	entity_service.container = world.get_node("Animals")
	render_service.container = entity_service.container
	debug_service.hud = debug_hud
	running = true
	compute_service.startup()
	if not compute_service.available():
		fail_step("GPU initialization failed: " + compute_service.failure)
		return
	animal_service.startup()
	job_service.startup()
	grid_service.startup()
	entity_service.startup()
	render_service.startup()
	profile_service.startup()
	debug_service.startup()
	reset_simulation()

func stop_simulation() -> void:
	running = false
	compute_service.shutdown()
	job_service.shutdown()
	entity_service.shutdown()
	animal_service.shutdown()
	debug_service.shutdown()
	profile_service.shutdown()
	render_service.shutdown()
	grid_service.shutdown()
	_pending_spawns.clear()
	_pending_config = null
	_reset_pending = false
	_step_pending = false
	_accumulator = 0.0

func reset_simulation() -> void:
	compute_service.reset()
	job_service.reset()
	debug_service.reset()
	entity_service.reset()
	render_service.reset()
	profile_service.reset()
	_accumulator = 0.0
	_clock_error_reported = false
	_pending_spawns.clear()
	_reset_pending = false
	_step_pending = false
	rng.seed = config.random_seed
	simulation_time = 0.0
	step_count = 0
	step_failed = false
	animal_service.reset()
	reset_frequency_window()
	paused = false
	entity_service.spawn_initial()
	render_service.sync()

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
	compute_service.reset()
	job_service.invalidate_async()
	animal_service.reset()
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
	if not is_finite(interval) or interval <= 0.0 or config.max_steps_per_frame <= 0 or not is_finite(delta) or delta < 0.0:
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
		if render_service.dirty:
			render_service.sync()
		return

	# 2) Calculate a bounded step count and retain only the fractional remainder.
	_accumulator += delta
	var pending_steps := floorf(_accumulator / interval + 0.000000001)
	var steps := int(minf(pending_steps, float(config.max_steps_per_frame)))
	_accumulator = maxf(0.0, _accumulator - pending_steps * interval)
	var frame_started := Time.get_ticks_usec()
	for index in range(steps):
		simulate_step(interval)

	# 3) Synchronize presentation once after all fixed steps in this display frame.
	if render_service.dirty:
		render_service.sync()
	var frame_ms := (Time.get_ticks_usec() - frame_started) / 1000.0
	profile_service.record_duration("Frames/SimulationAndSync", frame_ms)
	simulation_frame_completed.emit(frame_ms)

func fail_step(message: String) -> void:
	if step_failed:
		return

	step_failed = true
	paused = true
	running = false
	var details := "%s\n\nRenderer: %s\nGPU: %s" % [message, RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()]
	push_error(details)
	call_deferred("_show_compute_error", details)

func _show_compute_error(message: String) -> void:
	if DisplayServer.get_name() != "headless":
		OS.alert(message, "GPU Compute Error")
	get_tree().quit(1)

func simulate_step(delta: float) -> void:
	if step_failed:
		return

	profile_service.begin_step()
	entity_service.remove_expired()
	profile_service.end_stage("ExpiredCleanup")

	# 1) Commit completed logic without waiting, then advance animal time.
	animal_service.apply_completed()
	if step_failed:
		return

	profile_service.end_stage("ApplyCompleted")
	animal_service.advance_time(delta)
	if step_failed:
		return

	profile_service.end_stage("AdvanceTime")
	animal_service.schedule_updates(delta)
	if step_failed:
		return

	profile_service.end_stage("ScheduleUpdates")

	# 2) Move using the latest valid intent, independently of background work.
	animal_service.prepare_motion(delta)
	profile_service.end_stage("Steering")
	entity_service.update_movement(delta)
	if step_failed:
		return

	profile_service.end_stage("Movement")

	# 3) Resolve captures after movement, then compact rows before the next step.
	animal_service.resolve_interactions(delta)
	profile_service.end_stage("Interaction")
	entity_service.remove_expired(delta)
	profile_service.end_stage("Cleanup")

	render_service.mark_dirty()
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

func advance_decision(animal: AnimalEntity) -> void:
	animal_service.advance_decision(animal)

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
