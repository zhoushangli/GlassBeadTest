@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.RETREAT

func _execute(delta: float) -> void:
	var wolf := agent as WolfController
	wolf.end_hunt(false)
	wolf.retreating = true
	if wolf.is_live(wolf.nearest_threat):
		var away := (wolf.global_position - wolf.nearest_threat.global_position).normalized()
		if away.is_zero_approx():
			away = wolf.facing
		wolf.move_towards(wolf.global_position + away * 100.0, wolf.settings.retreat_speed, delta)
