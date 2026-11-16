@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.DRIVE

func _execute(delta: float) -> void:
	var dog := agent as SheepdogController
	dog.move_towards(dog.last_seen_position, dog.settings.drive_speed, delta)
