extends Node

signal simulation_stepped
signal configuration_applied(restarted: bool)

const PRESET_PATH := "user://CFG_Runtime.tres"

@export var config: SimulationConfig
@onready var entity_service: EntityService = $EntityService
@onready var debug_service: DebugService = $DebugService
@onready var profile_service: ProfileService = $ProfileService

var defaults: SimulationConfig
var rng := RandomNumberGenerator.new()
var running: bool = false
var paused: bool = false
var simulation_time: float = 0.0
var step_count: int = 0
var _pending_spawns: Array[Vector2i] = []
var _pending_config: SimulationConfig
var _reset_pending: bool = false
var _step_pending: bool = false

func start_simulation(world: Node2D, debug_hud: DebugHUD, settings: SimulationConfig) -> void:
	stop_simulation()
	var error := settings.validate()
	if not error.is_empty():
		push_error(error)
		return

	defaults = settings.copy_config()
	config = settings.copy_config()
	entity_service.initialize(self, world.get_node("Animals"))
	running = true
	profile_service.initialize(self)
	reset_simulation()
	debug_service.initialize(self, debug_hud)

func stop_simulation() -> void:
	running = false
	profile_service.stop()
	_pending_spawns.clear()
	_pending_config = null
	_reset_pending = false
	_step_pending = false
	debug_service.clear_selection()
	if is_instance_valid(entity_service.container):
		entity_service.clear()
	debug_service.hud = null

func reset_simulation() -> void:
	debug_service.clear_selection()
	entity_service.clear()
	_pending_spawns.clear()
	_reset_pending = false
	_step_pending = false
	rng.seed = config.random_seed
	simulation_time = 0.0
	step_count = 0
	profile_service.reset_performance_stats()
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
			animal.refresh_config()
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

func request_spawn(kind: AnimalController.Kind, count: int) -> void:
	_pending_spawns.append(Vector2i(kind, count))

func request_reset() -> void:
	_reset_pending = true

func request_single_step() -> void:
	if paused:
		_step_pending = true

func random_position() -> Vector2:
	return Vector2(rng.randf_range(24.0, config.arena_size.x - 24.0),
		rng.randf_range(100.0, config.arena_size.y - 65.0))

func _physics_process(delta: float) -> void:
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

	if not paused:
		simulate_step(delta)
	elif _step_pending:
		_step_pending = false
		simulate_step(1.0 / 60.0)

func simulate_step(delta: float) -> void:
	profile_service.begin_step()
	# 1) Sample one shared position/velocity snapshot, then resolve dog claims.
	entity_service.rebuild_spatial_index()
	profile_service.end_stage("SpatialBuild")
	for animal in entity_service.entities:
		if animal.alive:
			animal.perceive(delta)
	profile_service.end_stage("Perception")
	entity_service.assign_dog_tasks()
	profile_service.end_stage("TaskAssignment")

	# 2) Produce movement intent, then move every animal.
	for animal in entity_service.entities:
		if animal.alive:
			animal.decide(delta)
	profile_service.end_stage("Decision")
	for animal in entity_service.entities:
		animal.move(delta)
	profile_service.end_stage("Movement")

	# 3) Resolve howls and captures at the resulting positions.
	for animal in entity_service.entities:
		if animal.alive:
			animal.resolve_interactions(delta)
	profile_service.end_stage("Interaction")
	entity_service.remove_expired()
	simulation_time += delta
	step_count += 1
	profile_service.end_step()
	simulation_stepped.emit()
