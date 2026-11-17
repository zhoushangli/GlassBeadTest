@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.DRIVE

func _execute(delta: float) -> void:
	var dog := animal
	var settings: SheepdogConfig = data.settings[dog.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.move_towards(dog, data.memory_last_seen_position[dog.row], settings.drive_speed, delta)
