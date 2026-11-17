class_name Job
extends RefCounted

enum State { IDLE, PENDING, WORKING, COMPLETED, APPLIED, DISCARDED }

var stage: StringName
var batch: int = 0
# Map each output index to its input row; asynchronous rows belong to the snapshot.
# e.g. rows = PackedInt32Array([7, 2]) maps output index 1 to snapshot row 2.
var rows := PackedInt32Array()
var snapshot: AnimalSnapshot
var grid: GridSnapshot
var config: SimulationConfig
var common: AnimalSystem
var delta: float = 0.0
var distance: float = 0.0
var interval: float = 0.0
var spatial_stats: bool = false
var detailed: bool = false
var version: int = -1
var sequence: int = 0
var submitted_usec: int = 0
var execution_started_usec: int = 0
var execution_finished_usec: int = 0
var grid_ms: float = 0.0
var stats: Dictionary = {}
var execute_ms: float = 0.0
var target: Object
var task_id: int = -1
var state: State = State.IDLE

func execute() -> void:
	assert(false, "Job.execute must be implemented")

func run_profiled() -> void:
	execution_started_usec = Time.get_ticks_usec()
	execute()
	execution_finished_usec = Time.get_ticks_usec()

func apply_result() -> void:
	assert(false, "Job.apply_result must be implemented")

func release_input() -> void:
	rows = PackedInt32Array()
	snapshot = null
	grid = null
	config = null
	common = null
	target = null

func copy_input(source: Job) -> void:
	snapshot = source.snapshot
	grid = source.grid
	config = source.config
	common = source.common
	delta = source.delta
	distance = source.distance
	interval = source.interval
	spatial_stats = source.spatial_stats
	detailed = source.detailed

func can_start() -> bool:
	return true

func cancel() -> void:
	pass

func is_cancelled() -> bool:
	return false
