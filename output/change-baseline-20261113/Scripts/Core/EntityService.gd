class_name EntityService
extends Node

@export var sheep_scene: PackedScene
@export var wolf_scene: PackedScene
@export var sheepdog_scene: PackedScene

var entities: Array[AnimalController] = []
var gameplay_engine: Node
var container: Node2D
var next_id: int = 1
var capture_count: int = 0


func initialize(engine: Node, entity_container: Node2D) -> void:
	gameplay_engine = engine
	container = entity_container


func spawn(kind: AnimalController.Kind, count: int, at_position := Vector2.INF) -> Array[AnimalController]:
	var result: Array[AnimalController] = []
	var scene: PackedScene = [sheep_scene, wolf_scene, sheepdog_scene][kind]
	if scene == null or not is_instance_valid(container):
		push_error("EntityService requires animal prefabs and an entity container.")
		return result

	for index in range(count):
		var animal := scene.instantiate() as AnimalController
		var spawn_position: Vector2 = at_position
		if spawn_position == Vector2.INF:
			spawn_position = gameplay_engine.random_position()
		animal.initialize(gameplay_engine, next_id, spawn_position)
		next_id += 1
		container.add_child(animal)
		entities.append(animal)
		result.append(animal)

	return result


func spawn_initial() -> void:
	var settings: SimulationConfig = gameplay_engine.config
	var center: Vector2 = settings.arena_size * 0.5
	for index in range(settings.initial_sheep):
		var point := center + Vector2(
			gameplay_engine.rng.randf_range(-220.0, 220.0),
			gameplay_engine.rng.randf_range(-120.0, 120.0))
		spawn(AnimalController.Kind.SHEEP, 1, point)

	for index in range(settings.initial_wolves):
		var point: Vector2 = gameplay_engine.random_position()
		if index % 2 == 0:
			point.x = 40.0
		else:
			point.x = settings.arena_size.x - 40.0
		spawn(AnimalController.Kind.WOLF, 1, point)

	for index in range(settings.initial_sheepdogs):
		var angle := TAU * float(index) / maxf(1.0, settings.initial_sheepdogs)
		spawn(AnimalController.Kind.SHEEPDOG, 1, center + Vector2.from_angle(angle) * 100.0)


func get_counts() -> Vector3i:
	var counts := Vector3i.ZERO
	for animal in entities:
		if animal.alive:
			counts[animal.kind] += 1
	return counts


func capture(prey: AnimalController) -> bool:
	if not is_instance_valid(prey) or not prey.alive or prey.kind != AnimalController.Kind.SHEEP:
		return false

	prey.die()
	capture_count += 1
	gameplay_engine.debug_service.clear_invalid_selection()
	return true


func remove_expired() -> void:
	for index in range(entities.size() - 1, -1, -1):
		var animal: AnimalController = entities[index]
		if not animal.alive and animal.death_remaining <= 0.0:
			entities.remove_at(index)
			container.remove_child(animal)
			animal.queue_free()


func clear() -> void:
	for animal in entities:
		container.remove_child(animal)
		animal.queue_free()
	entities.clear()
	next_id = 1
	capture_count = 0
