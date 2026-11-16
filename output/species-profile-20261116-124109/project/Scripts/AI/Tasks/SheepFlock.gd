@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.FLOCK

func _execute(_delta: float) -> void:
	var sheep := agent.entity as AnimalEntity
	data.motion_intent[sheep.row] = AnimalData.MotionIntent.SHEEP
	data.motion_movement_goal[sheep.row] = g_gameplayEngine.animal_system.get_wander_point(sheep, 85.0)
