class_name Service
extends Node2D

var started: bool = false

func startup() -> void:
	if started:
		return
	started = true
	_startup()

func reset() -> void:
	if started:
		_reset()

func shutdown() -> void:
	if not started:
		return
	started = false
	_shutdown()

func _exit_tree() -> void:
	shutdown()

func _startup() -> void:
	pass

func _reset() -> void:
	pass

func _shutdown() -> void:
	pass
