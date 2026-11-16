extends Node

signal simulation_stepped
signal configuration_applied(restarted: bool)

const PRESET_PATH := "user://CFG_Runtime.tres"

@export var config: SimulationConfig
@export_range(1.0, 240.0, 1.0) var simulation_hz: float = 60.0
@export_range(1, 16, 1) var max_steps_per_frame: int = 4
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
		paused = value
var simulation_time: float = 0.0
var step_count: int = 0
var _pending_spawns: Array[Vector2i] = []
var _pending_config: SimulationConfig
var _reset_pending: bool = false
var _step_pending: bool = false
var _accumulator: float = 0.0
var _clock_error_reported: bool = false
var ecs_world: World
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
	_create_ecs_world()
	running = true
	entity_service.startup()
	profile_service.startup()
	debug_service.startup()
	reset_simulation()

func stop_simulation() -> void:
	running = false
	debug_service.shutdown()
	profile_service.shutdown()
	entity_service.shutdown()
	if is_instance_valid(ecs_world):
		ECS.world = null
		ecs_world.queue_free()
	ecs_world = null
	_pending_spawns.clear()
	_pending_config = null
	_reset_pending = false
	_step_pending = false
	_accumulator = 0.0

func reset_simulation() -> void:
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

	# 1) Apply UI commands before iterating entities, including while paused.
	if _pending_config != null:
		_apply_pending_config()
	if _reset_pending:
		reset_simulation()
	for request in _pending_spawns:
		entity_service.spawn(request.x, request.y)
	_pending_spawns.clear()

	var interval := 1.0 / simulation_hz if is_finite(simulation_hz) and simulation_hz > 0.0 else 0.0
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
	# 1) Sample one shared position/velocity snapshot, then resolve dog claims.
	entity_service.rebuild_spatial_index()
	profile_service.end_stage("SpatialBuild")
	ecs_world.process(delta, "perception")
	profile_service.end_stage("Perception")
	dog_system.assign_tasks()
	profile_service.end_stage("TaskAssignment")

	# 2) Produce movement intent, then move every animal.
	ecs_world.process(delta, "decision")
	profile_service.end_stage("Decision")
	ecs_world.process(delta, "movement")
	profile_service.end_stage("Movement")

	# 3) Resolve howls and captures at the resulting positions.
	ecs_world.process(delta, "interaction")
	profile_service.end_stage("Interaction")
	entity_service.remove_expired(delta)
	ecs_world.process(delta, "presentation")
	debug_service.advance_visuals(delta)
	simulation_time += delta
	step_count += 1
	profile_service.end_step()
	simulation_stepped.emit()

func _create_ecs_world() -> void:
	ecs_world = World.new()
	add_child(ecs_world)
	ECS.world = ecs_world
	animal_system = AnimalSystem.new()
	sheep_system = SheepSystem.new()
	wolf_system = WolfSystem.new()
	dog_system = SheepdogSystem.new()
	for system: System in [sheep_system, wolf_system, dog_system]:
		system.group = "perception"
		ecs_world.add_system(system)
	animal_system.group = "movement"
	ecs_world.add_system(animal_system)
	for stage in AnimalStageSystem.Stage.values():
		var system := AnimalStageSystem.new()
		system.stage = stage
		system.group = ["decision", "interaction", "presentation"][stage]
		ecs_world.add_system(system)

func refresh_animal_config(animal: AnimalEntity) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	data.settings[row] = [config.sheep, config.wolf, config.sheepdog][data.identity_kind[row]]
	data.memory_perception_ready[row] = false
	data.memory_vision_radius_squared[row] = data.settings[row].perception_radius * data.settings[row].perception_radius
	data.memory_vision_cos[row] = cos(deg_to_rad(data.settings[row].vision_angle * 0.5))
	if data.identity_kind[row] == AnimalEntity.Kind.SHEEPDOG:
		data.dog_assignment_remaining[row] = 0.0

func perceive_animal(animal: AnimalEntity, delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	match data.identity_kind[row]:
		AnimalEntity.Kind.SHEEP:
			sheep_system.perceive(animal, delta)
		AnimalEntity.Kind.WOLF:
			wolf_system.perceive(animal, delta)
		AnimalEntity.Kind.SHEEPDOG:
			dog_system.perceive(animal, delta)

func debug_details(animal: AnimalEntity) -> String:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var system: System = [sheep_system, wolf_system, dog_system][data.identity_kind[row]]
	return system.call("get_debug_details", animal)
