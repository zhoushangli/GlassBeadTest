@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.STALK

func _execute(delta: float) -> void:
	var wolf := agent.entity as AnimalEntity
	var settings: WolfConfig = data.settings[wolf.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if data.wolf_strategy[wolf.row] == AnimalEntity.Strategy.HOWL and not data.wolf_howled[wolf.row] and data.wolf_howl_elapsed[wolf.row] >= settings.howl_cooldown and data.motion_position[wolf.row].distance_to(data.memory_last_seen_position[wolf.row]) <= settings.howl_trigger_distance:
		data.wolf_howl_pending[wolf.row] = 1
		data.wolf_howled[wolf.row] = 1
		data.wolf_howl_elapsed[wolf.row] = 0.0
	common.move_towards(wolf, data.memory_last_seen_position[wolf.row], settings.move_speed, delta)
