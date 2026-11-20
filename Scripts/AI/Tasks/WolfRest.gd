@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.REST

func _execute(delta: float) -> void:
	var wolf := animal
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if data.wolf.retreating[wolf.row]:
		data.wolf.retreating[wolf.row] = 0
		data.wolf.resting[wolf.row] = 1
		data.wolf.rest_elapsed[wolf.row] = 0.0
	common.submit_velocity(wolf, Vector2.ZERO, 0.0)
