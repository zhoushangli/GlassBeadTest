@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.ALERT

func _execute(delta: float) -> void:
	var sheep := agent as SheepController
	var flock := sheep.get_flock_velocity() * sheep.settings.alert_flock_scale
	sheep.apply_steering(Vector2.ZERO, flock, sheep.move_speed, delta)
