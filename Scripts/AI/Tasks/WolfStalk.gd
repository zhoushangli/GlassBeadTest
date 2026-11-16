@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalController.Behavior.STALK

func _execute(delta: float) -> void:
	var wolf := agent as WolfController
	var point := wolf.last_seen_position
	var direction := wolf.last_seen_velocity.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	match wolf.strategy:
		WolfController.Strategy.SIDE:
			point += direction.orthogonal() * wolf.settings.strategy_offset
		WolfController.Strategy.REAR:
			point -= direction * wolf.settings.strategy_offset
		WolfController.Strategy.HOWL:
			if not wolf.howled and wolf.howl_elapsed >= wolf.settings.howl_cooldown and wolf.global_position.distance_to(wolf.last_seen_position) <= wolf.settings.howl_trigger_distance:
				wolf.howl_pending = true
				wolf.howled = true
				wolf.howl_elapsed = 0.0
	wolf.move_towards(wolf.clamp_to_arena(point), wolf.move_speed, delta)
