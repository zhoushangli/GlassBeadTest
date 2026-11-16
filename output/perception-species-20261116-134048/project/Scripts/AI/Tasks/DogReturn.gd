@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.RETURN

func _execute(delta: float) -> void:
	var dog := agent.entity as AnimalEntity
	var settings: SheepdogConfig = data.settings[dog.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.move_towards(dog, data.dog_guard_point[dog.row], settings.return_speed, delta)
