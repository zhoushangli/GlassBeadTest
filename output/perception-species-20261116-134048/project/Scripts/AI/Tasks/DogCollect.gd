@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.COLLECT

func _execute(delta: float) -> void:
	var dog := agent.entity as AnimalEntity
	var settings: SheepdogConfig = data.settings[dog.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if common.is_live(dog, data.live(data.dog_collected_sheep[dog.row])):
		common.move_towards(dog, data.motion_position[data.live(data.dog_collected_sheep[dog.row]).row], settings.move_speed, delta)
