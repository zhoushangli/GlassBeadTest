@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.PATROL

func _execute(delta: float) -> void:
	var dog := agent.entity as AnimalEntity
	var settings: SheepdogConfig = data.settings[dog.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if data.dog_region[dog.row] >= 0 or common.is_live(dog, data.live(data.dog_protected_sheep[dog.row])):
		common.move_towards(dog, data.dog_guard_point[dog.row], settings.move_speed, delta)
	else:
		var point: Vector2 = common.get_wander_point(dog, 85.0)
		common.move_towards(dog, point, settings.move_speed, delta)
