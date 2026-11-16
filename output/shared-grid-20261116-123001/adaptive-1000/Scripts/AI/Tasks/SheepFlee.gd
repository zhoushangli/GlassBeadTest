@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.FLEE

func _execute(_delta: float) -> void:
	var sheep := agent.entity as AnimalEntity
	data.motion_intent[sheep.row] = AnimalData.MotionIntent.SHEEP
