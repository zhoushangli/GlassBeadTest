@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.SEARCH

func _execute(delta: float) -> void:
	var wolf := agent as WolfController
	wolf.move_towards(wolf.last_seen_position, wolf.move_speed, delta)
