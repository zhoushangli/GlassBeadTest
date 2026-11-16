@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.HERDED

func _execute(delta: float) -> void:
	var sheep := agent as SheepController
	var flock := sheep.get_flock_velocity()
	var steering := sheep.dog_pressure * sheep.move_speed * sheep.settings.dog_pressure_weight
	sheep.apply_steering(steering, flock, sheep.move_speed, delta)
