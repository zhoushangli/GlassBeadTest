@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.RETREAT

func _execute(delta: float) -> void:
	var wolf := agent.entity as AnimalEntity
	var settings: WolfConfig = data.settings[wolf.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var wolf_system: WolfSystem = g_gameplayEngine.wolf_system
	wolf_system.end_hunt(wolf, false)
	data.wolf_retreating[wolf.row] = 1
	if common.is_live(wolf, data.live(data.wolf_nearest_threat[wolf.row])):
		var away := (data.motion_position[wolf.row] - data.motion_position[data.live(data.wolf_nearest_threat[wolf.row]).row]).normalized()
		if away.is_zero_approx():
			away = data.motion_facing[wolf.row]
		common.move_towards(wolf, data.motion_position[wolf.row] + away * 100.0, settings.retreat_speed, delta)
