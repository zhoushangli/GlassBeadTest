extends Node

signal simulation_stepped
signal grass_reset
signal grass_changed(index: int)
signal configuration_applied(restarted: bool)

const PRESET_PATH := "user://CFG_Runtime.tres"

@export var config: SimulationConfig
@onready var entity_service: EntityService = $EntityService
@onready var debug_service: DebugService = $DebugService

var defaults: SimulationConfig
var rng := RandomNumberGenerator.new()
var running: bool = false
var paused: bool = false
var simulation_time: float = 0.0
var step_count: int = 0
var last_step_ms: float = 0.0
var last_perception_ms: float = 0.0
var last_decision_ms: float = 0.0
var last_movement_ms: float = 0.0
var hud: DebugHUD
var grass_positions := PackedVector2Array()
var grass_patch_indices := PackedInt32Array()
var grass_bites := PackedInt32Array()
var grass_claims := PackedInt32Array()
var grass_regrow_remaining := PackedFloat32Array()
var _pending_spawns: Array[Vector2i] = []
var _pending_config: SimulationConfig
var _reset_pending: bool = false
var _step_pending: bool = false
var performance_stats_enabled: bool = OS.is_debug_build()
var performance_monitors: Dictionary = {
	"Simulation/StepMeanMs": 0.0, "Simulation/StepMaxMs": 0.0,
	"Spatial/QueriesPerStep": 0.0, "Spatial/CandidatesPerQuery": 0.0,
	"Spatial/MaxCandidates": 0.0, "Spatial/NonemptyCells": 0.0,
	"Spatial/MaxCellOccupancy": 0.0,
}
var _stats_window_started: int = 0
var _stats_steps: int = 0
var _stats_step_total: float = 0.0
var _stats_step_max: float = 0.0
var _stats_queries: int = 0
var _stats_candidates: int = 0
var _stats_max_candidates: int = 0
var _stats_cells: int = 0
var _stats_max_occupancy: int = 0

func start_simulation(world: Node2D, debug_hud: DebugHUD, settings: SimulationConfig) -> void:
	stop_simulation()
	var error := settings.validate()
	if not error.is_empty():
		push_error(error)
		return

	defaults = settings.copy_config()
	config = settings.copy_config()
	hud = debug_hud
	entity_service.initialize(self, world.get_node("Animals"))
	debug_service.initialize(self)
	running = true
	set_performance_stats_enabled(performance_stats_enabled)
	reset_simulation()
	hud.initialize(self)

func stop_simulation() -> void:
	running = false
	for id in performance_monitors:
		if Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)
	_pending_spawns.clear()
	_pending_config = null
	_reset_pending = false
	_step_pending = false
	debug_service.clear_selection()
	if is_instance_valid(entity_service.container):
		entity_service.clear()
	hud = null

func reset_simulation() -> void:
	debug_service.clear_selection()
	entity_service.clear()
	_pending_spawns.clear()
	_reset_pending = false
	_step_pending = false
	rng.seed = config.random_seed
	simulation_time = 0.0
	step_count = 0
	last_step_ms = 0.0
	last_perception_ms = 0.0
	last_decision_ms = 0.0
	last_movement_ms = 0.0
	reset_performance_stats()
	paused = false
	reset_grass()
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

func reset_grass() -> void:
	grass_positions.clear()
	grass_patch_indices.clear()
	grass_bites.clear()
	grass_claims.clear()
	grass_regrow_remaining.clear()

	for patch in range(config.grass.positions.size()):
		var center := config.grass.positions[patch]
		for index in range(config.grass.per_patch):
			var radius := maxf(0.0, config.grass.patch_radius - 10.0) * sqrt(float(index) / maxi(1, config.grass.per_patch - 1))
			grass_positions.append(center + Vector2.from_angle(index * 2.399963) * radius)
			grass_patch_indices.append(patch)
			grass_bites.append(config.grass.bites)
			grass_claims.append(0)
			grass_regrow_remaining.append(0.0)
	grass_reset.emit()

func consume_grass(index: int) -> bool:
	if index < 0 or index >= grass_bites.size() or grass_bites[index] <= 0:
		return false
	grass_bites[index] -= 1
	if grass_bites[index] == 0:
		grass_regrow_remaining[index] = config.grass.regrow_duration
	grass_changed.emit(index)
	return true

func _update_grass(delta: float) -> void:
	for index in range(grass_bites.size()):
		if grass_bites[index] > 0:
			continue
		grass_regrow_remaining[index] = maxf(0.0, grass_regrow_remaining[index] - delta)
		if grass_regrow_remaining[index] <= 0.00001:
			grass_regrow_remaining[index] = 0.0
			grass_bites[index] = config.grass.bites
			grass_changed.emit(index)

func rebuild_grass_claims() -> void:
	grass_claims.fill(0)
	for sheep in entity_service.sheep:
		if sheep.alive and sheep.grass_target_index >= 0 and sheep.grass_target_index < grass_claims.size():
			grass_claims[sheep.grass_target_index] += 1

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
	var started := Time.get_ticks_usec()
	# 1) Prepare one shared snapshot, then select wolf targets before animal perception.
	_update_grass(delta)
	entity_service.rebuild_spatial_index()
	rebuild_grass_claims()
	for wolf in entity_service.wolves:
		if wolf.alive:
			wolf.update_hunt(delta)
	for animal in entity_service.entities:
		if animal.alive:
			animal.perceive(delta)
	var perceived := Time.get_ticks_usec()

	# 2) Produce movement intent, then move every animal.
	for animal in entity_service.entities:
		if animal.alive:
			animal.decide(delta)
	var decided := Time.get_ticks_usec()
	for animal in entity_service.entities:
		animal.move(delta)

	# 3) Resolve meals and captures at the resulting positions.
	for animal in entity_service.entities:
		if animal.alive:
			animal.resolve_interactions(delta)
	entity_service.remove_expired()
	simulation_time += delta
	step_count += 1
	var finished := Time.get_ticks_usec()
	last_perception_ms = (perceived - started) / 1000.0
	last_decision_ms = (decided - perceived) / 1000.0
	last_movement_ms = (finished - decided) / 1000.0
	last_step_ms = (finished - started) / 1000.0
	if performance_stats_enabled:
		_record_performance_step()
	simulation_stepped.emit()

func set_performance_stats_enabled(enabled: bool) -> void:
	performance_stats_enabled = enabled
	entity_service.spatial_stats_enabled = enabled
	reset_performance_stats()
	for id in performance_monitors:
		if Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)
		if enabled and running:
			Performance.add_custom_monitor(id, _get_performance_monitor.bind(id))

func _get_performance_monitor(id: String) -> float:
	return performance_monitors[id]

func reset_performance_stats() -> void:
	for id in performance_monitors:
		performance_monitors[id] = 0.0
	entity_service.reset_spatial_stats()
	_reset_stats_window()

func _reset_stats_window() -> void:
	_stats_window_started = Time.get_ticks_usec()
	_stats_steps = 0
	_stats_step_total = 0.0
	_stats_step_max = 0.0
	_stats_queries = 0
	_stats_candidates = 0
	_stats_max_candidates = 0
	_stats_cells = 0
	_stats_max_occupancy = 0

func _record_performance_step() -> void:
	_stats_steps += 1
	_stats_step_total += last_step_ms
	_stats_step_max = maxf(_stats_step_max, last_step_ms)
	_stats_queries += entity_service.spatial_query_count
	_stats_candidates += entity_service.spatial_candidate_count
	_stats_max_candidates = maxi(_stats_max_candidates, entity_service.spatial_max_candidates)
	_stats_cells += entity_service.spatial_nonempty_cells
	_stats_max_occupancy = maxi(_stats_max_occupancy, entity_service.spatial_max_occupancy)
	if Time.get_ticks_usec() - _stats_window_started < 1000000:
		return
	performance_monitors["Simulation/StepMeanMs"] = _stats_step_total / _stats_steps
	performance_monitors["Simulation/StepMaxMs"] = _stats_step_max
	performance_monitors["Spatial/QueriesPerStep"] = float(_stats_queries) / _stats_steps
	performance_monitors["Spatial/CandidatesPerQuery"] = float(_stats_candidates) / maxi(1, _stats_queries)
	performance_monitors["Spatial/MaxCandidates"] = _stats_max_candidates
	performance_monitors["Spatial/NonemptyCells"] = float(_stats_cells) / _stats_steps
	performance_monitors["Spatial/MaxCellOccupancy"] = _stats_max_occupancy
	_reset_stats_window()

func _process(_delta: float) -> void:
	if running:
		debug_service.refresh()
		if is_instance_valid(hud):
			hud.refresh()
