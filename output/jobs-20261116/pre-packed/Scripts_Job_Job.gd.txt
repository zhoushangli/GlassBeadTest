class_name Job
extends RefCounted

enum State { IDLE, PENDING, WORKING, COMPLETED, APPLIED, DISCARDED }

var stage: StringName
var batch: int = 0
var rows := PackedInt32Array()
var context: Dictionary = {}
var result: Dictionary = {}
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
