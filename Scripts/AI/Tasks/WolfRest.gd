@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.REST

func _execute(delta: float) -> void:
	var wolf := agent as WolfController
	if wolf.retreating:
		wolf.retreating = false
		wolf.resting = true
		wolf.rest_elapsed = 0.0
	wolf.submit_velocity(Vector2.ZERO, 0.0)
