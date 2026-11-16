@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.CHASE

func _execute(delta: float) -> void:
	var wolf := agent as WolfController
	wolf.charging = true
	wolf.move_towards(wolf.last_seen_position, wolf.settings.chase_speed, delta)
