class_name Job
extends RefCounted

enum State { IDLE, PENDING, WORKING, COMPLETED, APPLIED, DISCARDED }

var stage: StringName
var batch: int = 0
# Map each output index to its input row; asynchronous rows belong to the snapshot.
# e.g. rows = PackedInt32Array([7, 2]) maps output index 1 to snapshot row 2.
var rows := PackedInt32Array()
var context: Dictionary = {}
var stats: Dictionary = {}
var execute_ms: float = 0.0
var target: Object
var task_id: int = -1
var state: State = State.IDLE

func execute() -> void:
	assert(false, "Job.execute must be implemented")

func apply_result() -> void:
	assert(false, "Job.apply_result must be implemented")

func release_input() -> void:
	rows = PackedInt32Array()
	context = {}
	target = null
