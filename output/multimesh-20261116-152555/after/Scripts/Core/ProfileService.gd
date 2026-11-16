class_name ProfileService
extends Service

const STAGE_NAMES := ["SpatialBuild", "TaskAssignment", "Perception", "Decision", "Steering", "Movement", "Interaction", "Cleanup", "RenderSync"]
const HOTSPOT_NAMES := ["NearbyQuery", "NeighborScan", "Separation", "WolfTarget", "DogAnchor"]

var last_step_ms: float = 0.0
var last_perception_ms: float = 0.0
var last_decision_ms: float = 0.0
var last_movement_ms: float = 0.0

var _step_started: int = 0
var _stage_started: int = 0
var _decision_started: int = 0
var _movement_started: int = 0

var performance_stats_enabled: bool = OS.is_debug_build()
var detailed_stats_enabled: bool = false
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

func _startup() -> void:
	set_performance_stats_enabled(performance_stats_enabled, detailed_stats_enabled)

func _shutdown() -> void:
	for id in performance_monitors:
		if Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)

func _process(_delta: float) -> void:
	if started and g_gameplayEngine.running and performance_stats_enabled:
		_publish_performance_stats()

func begin_step() -> void:
	_step_started = Time.get_ticks_usec()
	_decision_started = _step_started
	_stage_started = _step_started
	if detailed_stats_enabled:
		for metric in HOTSPOT_NAMES:
			last_hotspots_ms[metric] = 0.0
			last_hotspot_calls[metric] = 0

func end_stage(metric: String) -> void:
	var finished := Time.get_ticks_usec()
	if performance_stats_enabled:
		last_stages_ms[metric] = (finished - _stage_started) / 1000.0

	match metric:
		"Perception":
			last_perception_ms = (finished - _step_started) / 1000.0
		"TaskAssignment":
			_decision_started = finished
		"Decision":
			last_decision_ms = (finished - _decision_started) / 1000.0
		"Steering":
			_movement_started = finished
	_stage_started = finished

func end_step() -> void:
	var finished := Time.get_ticks_usec()
	if performance_stats_enabled:
		last_stages_ms["Cleanup"] += (finished - _stage_started) / 1000.0
	_stage_started = finished
	last_step_ms = (_stage_started - _step_started) / 1000.0
	last_movement_ms = (_stage_started - _movement_started) / 1000.0
	if performance_stats_enabled:
		_record_performance_step()

func set_performance_stats_enabled(enabled: bool, detailed: bool = false) -> void:
	performance_stats_enabled = enabled
	detailed_stats_enabled = enabled and detailed
	g_gameplayEngine.grid_service.spatial_stats_enabled = enabled

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
	reset()

	for id in performance_monitors:
		if Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)
		if enabled and started and g_gameplayEngine.running:
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

func _reset() -> void:
	last_step_ms = 0.0
	last_perception_ms = 0.0
	last_decision_ms = 0.0
	last_movement_ms = 0.0

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
	g_gameplayEngine.grid_service.reset_spatial_stats()
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

	_stats_queries += g_gameplayEngine.grid_service.spatial_query_count
	_stats_candidates += g_gameplayEngine.grid_service.spatial_candidate_count
	_stats_max_candidates = maxi(_stats_max_candidates, g_gameplayEngine.grid_service.spatial_max_candidates)
	_stats_cells += g_gameplayEngine.grid_service.spatial_nonempty_cells
	_stats_max_occupancy = maxi(_stats_max_occupancy, g_gameplayEngine.grid_service.spatial_max_occupancy)
	_publish_performance_stats()

func _publish_performance_stats() -> void:
	if Time.get_ticks_usec() - _stats_window_started < 1000000:
		return

	var counts: Vector3i = g_gameplayEngine.entity_service.get_counts()
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
