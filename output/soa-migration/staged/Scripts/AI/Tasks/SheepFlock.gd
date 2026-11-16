@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.FLOCK

func _execute(delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var sheep := agent.entity as AnimalEntity
	var settings: SheepConfig = data.settings[sheep.row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var sheep_system: SheepSystem = g_gameplayEngine.sheep_system
	var flock: Vector2 = sheep_system.get_flock_velocity(sheep)
	var point: Vector2 = common.get_wander_point(sheep, 85.0)
	var steering: Vector2 = (point - data.motion_position[sheep.row]).normalized() * settings.move_speed * settings.idle_speed_scale
	flock *= settings.idle_flock_scale
	sheep_system.apply_steering(sheep, steering, flock, settings.move_speed, delta)
