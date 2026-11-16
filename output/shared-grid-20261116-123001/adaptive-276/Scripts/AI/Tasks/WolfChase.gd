@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.CHASE

func _execute(delta: float) -> void:
	var wolf := agent.entity as AnimalEntity
	var settings: WolfConfig = data.settings[wolf.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	data.wolf_charging[wolf.row] = 1
	common.move_towards(wolf, data.memory_last_seen_position[wolf.row], settings.chase_speed, delta)
