class_name ProfileService
extends Service

const STAGE_NAMES := ["ExpiredCleanup", "ApplyCompleted", "AdvanceTime", "ScheduleUpdates", "Steering", "Movement", "Interaction", "Cleanup", "Finalize"]
const HOTSPOT_NAMES := ["NearbyQuery", "NeighborScan", "Separation", "WolfTarget", "DogAnchor"]

var last_step_ms: float = 0.0

var _step_started: int = 0
var _stage_started: int = 0

var capture_enabled: bool = false
var capture_samples_ms: Dictionary = {}
var capture_times_usec: Dictionary = {}
var counters: Dictionary = {}
var _event_totals: Dictionary = {}
var _event_calls: Dictionary = {}

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
	_stage_started = _step_started
	for metric in STAGE_NAMES:
		last_stages_ms[metric] = 0.0
	if detailed_stats_enabled:
		for metric in HOTSPOT_NAMES:
			last_hotspots_ms[metric] = 0.0
			last_hotspot_calls[metric] = 0

# Measure elapsed wall time since the preceding stage boundary within a simulation step.
# e.g. AdvanceTime includes animal_service.advance_time(), while frame-level render sync is separate.
func end_stage(metric: String) -> void:
	var finished := Time.get_ticks_usec()
	if performance_stats_enabled:
		last_stages_ms[metric] = (finished - _stage_started) / 1000.0

	_stage_started = finished

func end_step() -> void:
	var finished := Time.get_ticks_usec()
	if performance_stats_enabled:
		last_stages_ms["Finalize"] += (finished - _stage_started) / 1000.0
	_stage_started = finished
	last_step_ms = (_stage_started - _step_started) / 1000.0
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
	return id in ["Simulation/StepMean", "Simulation/StepP95", "Simulation/StepMax"] or id.begins_with("Profile/") or id.begins_with("SimStages/") or id.begins_with("Debug/") or (id.begins_with("Hotspots/") and id.ends_with("Mean"))

func begin_capture() -> void:
	capture_samples_ms.clear()
	capture_times_usec.clear()
	counters.clear()
	capture_enabled = true

func record_duration(metric: String, elapsed_ms: float) -> void:
	if not performance_stats_enabled or elapsed_ms < 0.0:
		return

	var id := "Profile/" + metric + "Mean"
	if not performance_monitors.has(id):
		performance_monitors[id] = 0.0
		if started and g_gameplayEngine.running:
			Performance.add_custom_monitor(id, _get_performance_monitor.bind(id), [], Performance.MONITOR_TYPE_TIME)
	_event_totals[metric] = _event_totals.get(metric, 0.0) + elapsed_ms
	_event_calls[metric] = _event_calls.get(metric, 0) + 1
	if capture_enabled:
		if not capture_samples_ms.has(metric):
			capture_samples_ms[metric] = []
			capture_times_usec[metric] = []
		capture_samples_ms[metric].append(elapsed_ms)
		capture_times_usec[metric].append(Time.get_ticks_usec())

func count_event(metric: String) -> void:
	if performance_stats_enabled:
		counters[metric] = counters.get(metric, 0) + 1

func capture_summary() -> Dictionary:
	var result: Dictionary = {}
	for metric in capture_samples_ms:
		var values: Array = capture_samples_ms[metric].duplicate()
		values.sort()
		var total: float = 0.0
		for value: float in values:
			total += value
		result[metric] = {"count": values.size(), "total_ms": total, "mean_ms": total / values.size(),
			"p95_ms": values[ceili(values.size() * 0.95) - 1], "max_ms": values.back()}
	return result

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
	record_duration("Debug/" + metric, elapsed)

func _reset() -> void:
	last_step_ms = 0.0
	capture_enabled = false
	capture_samples_ms.clear()
	capture_times_usec.clear()
	counters.clear()

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
	_event_totals.clear()
	_event_calls.clear()
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
		record_duration("Steps/" + metric, last_stages_ms[metric])

	record_duration("Steps/Total", last_step_ms)
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

	# 1) Publish the completed one-second window without mixing per-step and per-call means.
	var counts: Vector3i = g_gameplayEngine.entity_service.get_counts()
	performance_monitors["Simulation/AliveEntities"] = counts.x + counts.y + counts.z
	performance_monitors["Simulation/StepMean"] = _stats_step_total / maxi(1, _stats_steps)
	performance_monitors["Simulation/StepMax"] = _stats_step_max

	for id in performance_monitors:
		if id.begins_with("Profile/"):
			performance_monitors[id] = 0.0

	for metric in _event_totals:
		performance_monitors["Profile/" + metric + "Mean"] = _event_totals[metric] / _event_calls[metric]

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
