@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.FLOCK

func _execute(delta: float) -> void:
	var sheep := agent as SheepController
	var flock := sheep.get_flock_velocity()
	var point := sheep.get_wander_point(85.0)
	var steering := (point - sheep.global_position).normalized() * sheep.move_speed * sheep.settings.idle_speed_scale
	flock *= sheep.settings.idle_flock_scale
	sheep.apply_steering(steering, flock, sheep.move_speed, delta)
