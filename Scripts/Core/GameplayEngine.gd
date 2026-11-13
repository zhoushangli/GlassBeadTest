extends Node

signal simulation_stepped
signal grass_reset
signal grass_changed(index: int)
signal configuration_applied(restarted: bool)

const PRESET_PATH := "user://CFG_Runtime.tres"
const STAGE_NAMES := ["Preparation", "SpatialBuild", "HuntUpdate", "Perception", "Decision", "Movement", "Interaction", "Cleanup"]
const HOTSPOT_NAMES := ["NearbyQuery", "NeighborScan", "Separation", "WolfTarget", "DogAnchor", "SheepGrass"]

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
var detailed_stats_enabled: bool = false
var hud_enabled: bool = true
var overlay_enabled: bool = true
var last_stages_ms: Dictionary = {}
var last_hotspots_ms: Dictionary = {}
var last_hotspot_calls: Dictionary = {}
var debug_totals_ms: Dictionary = {"HUDRefresh": 0.0, "OverlayDrawCPUTime": 0.0}
var debug_calls: Dictionary = {"HUDRefresh": 0, "OverlayDrawCPUTime": 0}
var performance_monitors: Dictionary = {
	"Simulation/AliveEntities": 0.0,
	"Simulation/StepMean": 0.0, "Simulation/StepP95": 0.0, "Simulation/StepMax": 0.0,
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
var _stats_step_times: Array[float] = []
var _stats_stages: Dictionary = {}
var _stats_hotspots: Dictionary = {}
var _stats_hotspot_calls: Dictionary = {}
var _stats_debug_ms: Dictionary = {}
var _stats_debug_calls: Dictionary = {}

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
	set_performance_stats_enabled(performance_stats_enabled, detailed_stats_enabled)
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
	if detailed_stats_enabled:
		for metric in HOTSPOT_NAMES:
			last_hotspots_ms[metric] = 0.0
			last_hotspot_calls[metric] = 0
	# 1) Prepare one shared snapshot, then select wolf targets before animal perception.
	_update_grass(delta)
	var grass_updated := Time.get_ticks_usec() if performance_stats_enabled else started
	entity_service.rebuild_spatial_index()
	var indexed := Time.get_ticks_usec() if performance_stats_enabled else started
	rebuild_grass_claims()
	var prepared := Time.get_ticks_usec() if performance_stats_enabled else started
	for wolf in entity_service.wolves:
		if wolf.alive:
			wolf.update_hunt(delta)
	var hunted := Time.get_ticks_usec() if performance_stats_enabled else started
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
	var moved := Time.get_ticks_usec() if performance_stats_enabled else started

	# 3) Resolve meals and captures at the resulting positions.
	for animal in entity_service.entities:
		if animal.alive:
			animal.resolve_interactions(delta)
	var interacted := Time.get_ticks_usec() if performance_stats_enabled else started
	entity_service.remove_expired()
	simulation_time += delta
	step_count += 1
	var finished := Time.get_ticks_usec()
	last_perception_ms = (perceived - started) / 1000.0
	last_decision_ms = (decided - perceived) / 1000.0
	last_movement_ms = (finished - decided) / 1000.0
	last_step_ms = (finished - started) / 1000.0
	if performance_stats_enabled:
		last_stages_ms["Preparation"] = (grass_updated - started + prepared - indexed) / 1000.0
		last_stages_ms["SpatialBuild"] = (indexed - grass_updated) / 1000.0
		last_stages_ms["HuntUpdate"] = (hunted - prepared) / 1000.0
		last_stages_ms["Perception"] = (perceived - hunted) / 1000.0
		last_stages_ms["Decision"] = last_decision_ms
		last_stages_ms["Movement"] = (moved - decided) / 1000.0
		last_stages_ms["Interaction"] = (interacted - moved) / 1000.0
		last_stages_ms["Cleanup"] = (finished - interacted) / 1000.0
		_record_performance_step()
	simulation_stepped.emit()

func set_performance_stats_enabled(enabled: bool, detailed: bool = false) -> void:
	performance_stats_enabled = enabled
	detailed_stats_enabled = enabled and detailed
	entity_service.spatial_stats_enabled = enabled
	for metric in STAGE_NAMES:
		performance_monitors["SimStages/" + metric + "Mean"] = 0.0
	for metric in HOTSPOT_NAMES:
		for suffix in ["Mean", "CallsPerStep"]:
			var id: String = "Hotspots/" + metric + suffix
			if Performance.has_custom_monitor(id):
				Performance.remove_custom_monitor(id)
			performance_monitors.erase(id)
			if detailed_stats_enabled:
				performance_monitors[id] = 0.0
	for metric in debug_totals_ms:
		performance_monitors["Debug/" + metric + "Mean"] = 0.0
	reset_performance_stats()
	for id in performance_monitors:
		if Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)
		if enabled and running:
			var type := Performance.MONITOR_TYPE_QUANTITY
			if _is_time_monitor(id):
				type = Performance.MONITOR_TYPE_TIME
			Performance.add_custom_monitor(id, _get_performance_monitor.bind(id), [], type)

func _is_time_monitor(id: String) -> bool:
	return id in ["Simulation/StepMean", "Simulation/StepP95", "Simulation/StepMax"] or id.begins_with("SimStages/") or id.begins_with("Debug/") or (id.begins_with("Hotspots/") and id.ends_with("Mean"))

func _get_performance_monitor(id: String) -> float:
	# Return seconds for time monitors; the editor formats them as milliseconds.
	# e.g. 1.25 recorded milliseconds becomes 0.00125 seconds and displays as 1.25 ms.
	return performance_monitors[id] / 1000.0 if _is_time_monitor(id) else performance_monitors[id]

func record_hotspot(metric: String, started: int) -> void:
	last_hotspots_ms[metric] += (Time.get_ticks_usec() - started) / 1000.0
	last_hotspot_calls[metric] += 1

func record_debug_time(metric: String, started: int) -> void:
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	debug_totals_ms[metric] += elapsed
	debug_calls[metric] += 1
	_stats_debug_ms[metric] += elapsed
	_stats_debug_calls[metric] += 1

func reset_performance_stats() -> void:
	for id in performance_monitors:
		performance_monitors[id] = 0.0
	for metric in STAGE_NAMES:
		last_stages_ms[metric] = 0.0
	for metric in HOTSPOT_NAMES:
		last_hotspots_ms[metric] = 0.0
		last_hotspot_calls[metric] = 0
	for metric in debug_totals_ms:
		debug_totals_ms[metric] = 0.0
		debug_calls[metric] = 0
	entity_service.reset_spatial_stats()
	_reset_stats_window()

func _reset_stats_window() -> void:
	_stats_window_started = Time.get_ticks_usec()
	_stats_steps = 0
	_stats_step_total = 0.0
	_stats_step_max = 0.0
	_stats_step_times.clear()
	_stats_queries = 0
	_stats_candidates = 0
	_stats_max_candidates = 0
	_stats_cells = 0
	_stats_max_occupancy = 0
	for metric in STAGE_NAMES:
		_stats_stages[metric] = 0.0
	for metric in HOTSPOT_NAMES:
		_stats_hotspots[metric] = 0.0
		_stats_hotspot_calls[metric] = 0
	for metric in debug_totals_ms:
		_stats_debug_ms[metric] = 0.0
		_stats_debug_calls[metric] = 0

func _record_performance_step() -> void:
	_stats_steps += 1
	_stats_step_total += last_step_ms
	_stats_step_max = maxf(_stats_step_max, last_step_ms)
	_stats_step_times.append(last_step_ms)
	for metric in STAGE_NAMES:
		_stats_stages[metric] += last_stages_ms[metric]
	if detailed_stats_enabled:
		for metric in HOTSPOT_NAMES:
			_stats_hotspots[metric] += last_hotspots_ms[metric]
			_stats_hotspot_calls[metric] += last_hotspot_calls[metric]
	_stats_queries += entity_service.spatial_query_count
	_stats_candidates += entity_service.spatial_candidate_count
	_stats_max_candidates = maxi(_stats_max_candidates, entity_service.spatial_max_candidates)
	_stats_cells += entity_service.spatial_nonempty_cells
	_stats_max_occupancy = maxi(_stats_max_occupancy, entity_service.spatial_max_occupancy)
	_publish_performance_stats()

func _publish_performance_stats() -> void:
	if Time.get_ticks_usec() - _stats_window_started < 1000000:
		return
	var counts := entity_service.get_counts()
	performance_monitors["Simulation/AliveEntities"] = counts.x + counts.y + counts.z
	performance_monitors["Simulation/StepMean"] = _stats_step_total / maxi(1, _stats_steps)
	performance_monitors["Simulation/StepMax"] = _stats_step_max
	_stats_step_times.sort()
	performance_monitors["Simulation/StepP95"] = _stats_step_times[ceili(_stats_step_times.size() * 0.95) - 1] if not _stats_step_times.is_empty() else 0.0
	for metric in STAGE_NAMES:
		performance_monitors["SimStages/" + metric + "Mean"] = _stats_stages[metric] / maxi(1, _stats_steps)
	if detailed_stats_enabled:
		for metric in HOTSPOT_NAMES:
			performance_monitors["Hotspots/" + metric + "Mean"] = _stats_hotspots[metric] / maxi(1, _stats_steps)
			performance_monitors["Hotspots/" + metric + "CallsPerStep"] = float(_stats_hotspot_calls[metric]) / maxi(1, _stats_steps)
	for metric in debug_totals_ms:
		performance_monitors["Debug/" + metric + "Mean"] = _stats_debug_ms[metric] / maxi(1, _stats_debug_calls[metric])
	performance_monitors["Spatial/QueriesPerStep"] = float(_stats_queries) / maxi(1, _stats_steps)
	performance_monitors["Spatial/CandidatesPerQuery"] = float(_stats_candidates) / maxi(1, _stats_queries)
	performance_monitors["Spatial/MaxCandidates"] = _stats_max_candidates
	performance_monitors["Spatial/NonemptyCells"] = float(_stats_cells) / maxi(1, _stats_steps)
	performance_monitors["Spatial/MaxCellOccupancy"] = _stats_max_occupancy
	_reset_stats_window()

func _process(_delta: float) -> void:
	if running:
		if overlay_enabled:
			debug_service.refresh()
		if hud_enabled and is_instance_valid(hud):
			var started := Time.get_ticks_usec() if performance_stats_enabled else 0
			hud.refresh()
			if performance_stats_enabled:
				record_debug_time("HUDRefresh", started)
		if performance_stats_enabled:
			_publish_performance_stats()
