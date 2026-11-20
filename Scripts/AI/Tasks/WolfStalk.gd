@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.STALK

func _execute(delta: float) -> void:
	var wolf := animal
	var settings: WolfConfig = data.settings[wolf.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if data.wolf.strategy[wolf.row] == AnimalEntity.Strategy.HOWL and not data.wolf.howled[wolf.row] and data.wolf.howl_elapsed[wolf.row] >= settings.howl_cooldown and data.motion.position[wolf.row].distance_to(data.memory.last_seen_position[wolf.row]) <= settings.howl_trigger_distance:
		data.wolf.howl_pending[wolf.row] = 1
		data.wolf.howled[wolf.row] = 1
		data.wolf.howl_elapsed[wolf.row] = 0.0
	common.move_towards(wolf, data.memory.last_seen_position[wolf.row], settings.move_speed, delta)
