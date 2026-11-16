@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.FLEE

func _execute(delta: float) -> void:
	var sheep := agent as SheepController
	var flock := sheep.get_flock_velocity() * 0.25
	var steering := sheep.threat_direction.normalized() * sheep.settings.flee_speed * sheep.settings.wolf_pressure_weight
	sheep.apply_steering(steering, flock, sheep.settings.flee_speed, delta)
