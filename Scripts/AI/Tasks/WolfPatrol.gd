@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.PATROL

func _execute(delta: float) -> void:
	var wolf := animal
	var settings: WolfConfig = data.settings[wolf.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var point: Vector2 = common.get_wander_point(wolf, 160.0)
	common.move_towards(wolf, point, settings.move_speed * settings.patrol_speed_scale, delta)
