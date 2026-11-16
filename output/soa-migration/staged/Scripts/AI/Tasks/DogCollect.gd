@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.COLLECT

func _execute(delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var dog := agent.entity as AnimalEntity
	var settings: SheepdogConfig = data.settings[dog.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if common.is_live(dog, data.live(data.dog_collected_sheep[dog.row])):
		var away := (data.motion_position[data.live(data.dog_collected_sheep[dog.row]).row] - data.dog_protection_center[dog.row]).normalized()
		var point: Vector2 = common.clamp_to_arena(dog, data.motion_position[data.live(data.dog_collected_sheep[dog.row]).row] + away * settings.collect_distance)
		common.move_towards(dog, point, settings.move_speed, delta)
