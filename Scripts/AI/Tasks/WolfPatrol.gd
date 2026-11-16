@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.PATROL

func _execute(delta: float) -> void:
	var wolf := agent as WolfController
	var point := wolf.get_wander_point(160.0)
	wolf.move_towards(point, wolf.move_speed * wolf.settings.patrol_speed_scale, delta)
