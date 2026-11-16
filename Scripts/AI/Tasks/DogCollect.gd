@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.COLLECT

func _execute(delta: float) -> void:
	var dog := agent as SheepdogController
	if dog.is_live(dog.collected_sheep):
		var away := (dog.collected_sheep.global_position - dog.protection_center).normalized()
		var point := dog.clamp_to_arena(dog.collected_sheep.global_position + away * dog.settings.collect_distance)
		dog.move_towards(point, dog.move_speed, delta)
