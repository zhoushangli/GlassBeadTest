@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.PATROL

func _execute(delta: float) -> void:
	var dog := agent as SheepdogController
	if dog.is_live(dog.protected_sheep):
		dog.move_towards(dog.guard_point, dog.move_speed, delta)
	else:
		var point := dog.get_wander_point(85.0)
		dog.move_towards(point, dog.move_speed, delta)
