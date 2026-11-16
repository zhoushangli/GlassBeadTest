@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.ALERT

func _execute(delta: float) -> void:
	var sheep := agent.entity as AnimalEntity
	var settings: SheepConfig = data.settings[sheep.row]
	var sheep_system: SheepSystem = g_gameplayEngine.sheep_system
	var flock: Vector2 = sheep_system.get_flock_velocity(sheep) * settings.alert_flock_scale
	sheep_system.apply_steering(sheep, Vector2.ZERO, flock, settings.move_speed, delta)
