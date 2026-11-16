@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.RETURN

func _execute(delta: float) -> void:
	var dog := agent as SheepdogController
	dog.move_towards(dog.guard_point, dog.settings.return_speed, delta)
