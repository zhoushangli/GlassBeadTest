@tool
extends "res://Scripts/AI/Tasks/AnimalAction.gd"

func _init() -> void:
	behavior = AnimalEntity.Behavior.HERDED

func _execute(delta: float) -> void:
	var sheep := agent.entity as AnimalEntity
	var settings: SheepConfig = data.settings[sheep.row]
	var sheep_system: SheepSystem = g_gameplayEngine.sheep_system
	var flock: Vector2 = sheep_system.get_flock_velocity(sheep)
	var steering: Vector2 = data.sheep_dog_pressure[sheep.row] * settings.move_speed * settings.dog_pressure_weight
	sheep_system.apply_steering(sheep, steering, flock, settings.move_speed, delta)
