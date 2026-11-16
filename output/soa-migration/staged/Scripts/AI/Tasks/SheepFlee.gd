@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.FLEE

func _execute(delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var sheep := agent.entity as AnimalEntity
	var settings: SheepConfig = data.settings[sheep.row]
	var sheep_system: SheepSystem = g_gameplayEngine.sheep_system
	var flock: Vector2 = sheep_system.get_flock_velocity(sheep) * 0.25
	var steering: Vector2 = data.sheep_threat_direction[sheep.row].normalized() * settings.flee_speed * settings.wolf_pressure_weight
	sheep_system.apply_steering(sheep, steering, flock, settings.flee_speed, delta)
