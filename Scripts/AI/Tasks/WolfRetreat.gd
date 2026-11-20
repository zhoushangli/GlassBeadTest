@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.RETREAT

func _execute(delta: float) -> void:
	var wolf := animal
	var settings: WolfConfig = data.settings[wolf.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var wolf_system: WolfSystem = g_gameplayEngine.wolf_system
	wolf_system.end_hunt(wolf, false)
	data.wolf.retreating[wolf.row] = 1
	if common.is_live(wolf, data.live(data.wolf.nearest_threat[wolf.row])):
		common.move_towards(wolf, data.motion.position[wolf.row], settings.retreat_speed, delta)
