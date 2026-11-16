class_name EntityService
extends Service

const SPATIAL_CELL_SIZE: float = 120.0

@export var sheep_scene: PackedScene
@export var wolf_scene: PackedScene
@export var sheepdog_scene: PackedScene

var entities: Array[AnimalController] = []
var sheep: Array[SheepController] = []
var wolves: Array[WolfController] = []
var dogs: Array[SheepdogController] = []
var container: Node2D
var next_id: int = 1
var capture_count: int = 0
var perception_positions := PackedVector2Array()
var perception_velocities := PackedVector2Array()
var perception_kinds := PackedInt32Array()
var _spatial_cells: Dictionary[Vector2i, Array] = {}
var spatial_stats_enabled: bool = OS.is_debug_build()
var spatial_query_count: int = 0
var spatial_candidate_count: int = 0
var spatial_max_candidates: int = 0
var spatial_nonempty_cells: int = 0
var spatial_max_occupancy: int = 0

func _reset() -> void:
	clear()

func _shutdown() -> void:
	clear()
	container = null

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
			spawn_position = g_gameplayEngine.random_position()
		animal.initialize(next_id, spawn_position)
		next_id += 1
		container.add_child(animal)
		entities.append(animal)
		match kind:
			AnimalController.Kind.SHEEP:
				sheep.append(animal as SheepController)
			AnimalController.Kind.WOLF:
				wolves.append(animal as WolfController)
			AnimalController.Kind.SHEEPDOG:
				dogs.append(animal as SheepdogController)
		result.append(animal)

	return result

func spawn_initial() -> void:
	var settings: SimulationConfig = g_gameplayEngine.config
	var center: Vector2 = settings.arena_size * 0.5
	for index in range(settings.initial_sheep):
		var point := center + Vector2(
			g_gameplayEngine.rng.randf_range(-440.0, 440.0),
			g_gameplayEngine.rng.randf_range(-220.0, 220.0))
		spawn(AnimalController.Kind.SHEEP, 1, point)

	for index in range(settings.initial_wolves):
		var point: Vector2 = g_gameplayEngine.random_position()
		if index % 2 == 0:
			point.x = 40.0
		else:
			point.x = settings.arena_size.x - 40.0
		spawn(AnimalController.Kind.WOLF, 1, point)

	for index in range(settings.initial_sheepdogs):
		var angle := TAU * float(index) / maxf(1.0, settings.initial_sheepdogs)
		spawn(AnimalController.Kind.SHEEPDOG, 1, center + Vector2.from_angle(angle) * 100.0)

func rebuild_spatial_index() -> void:
	reset_spatial_stats()
	_spatial_cells.clear()
	perception_positions.resize(entities.size())
	perception_kinds.resize(entities.size())
	perception_velocities.resize(entities.size())

	for index in range(entities.size()):
		var animal := entities[index]
		if not animal.alive:
			continue

		var point := animal.global_position
		animal.perception_index = index
		perception_positions[index] = point
		perception_velocities[index] = animal.velocity
		perception_kinds[index] = animal.kind
		var cell := Vector2i((point / SPATIAL_CELL_SIZE).floor())
		if not _spatial_cells.has(cell):
			_spatial_cells[cell] = []
		_spatial_cells[cell].append(index)
		if spatial_stats_enabled:
			spatial_max_occupancy = maxi(spatial_max_occupancy, _spatial_cells[cell].size())
	if spatial_stats_enabled:
		spatial_nonempty_cells = _spatial_cells.size()

func reset_spatial_stats() -> void:
	spatial_query_count = 0
	spatial_candidate_count = 0
	spatial_max_candidates = 0
	spatial_nonempty_cells = 0
	spatial_max_occupancy = 0

func get_nearby_indices(point: Vector2, radius: float) -> Array[int]:
	var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
	var nearby: Array[int] = []
	var first := Vector2i(((point - Vector2.ONE * radius) / SPATIAL_CELL_SIZE).floor())
	var last := Vector2i(((point + Vector2.ONE * radius) / SPATIAL_CELL_SIZE).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if _spatial_cells.has(cell):
				nearby.append_array(_spatial_cells[cell])

	if spatial_stats_enabled:
		spatial_query_count += 1
		spatial_candidate_count += nearby.size()
		spatial_max_candidates = maxi(spatial_max_candidates, nearby.size())
	if g_gameplayEngine.profile_service.detailed_stats_enabled:
		g_gameplayEngine.profile_service.record_hotspot("NearbyQuery", started)
	return nearby

func assign_dog_tasks() -> void:
	var wolves_claimed: Dictionary = {}
	var sheep_claimed: Dictionary = {}
	var assignments: Dictionary = {}
	for dog in dogs:
		if dog.alive:
			assignments[dog] = [null, null]
	# 1) Resolve nearest wolf proposals, then farthest stray proposals.
	for kind in range(2):
		var claimed: Dictionary = wolves_claimed if kind == 0 else sheep_claimed
		var waiting: Array[SheepdogController] = []
		for dog: SheepdogController in assignments:
			if assignments[dog][0] == null and not dog._returning:
				waiting.append(dog)
		while not waiting.is_empty():
			var proposals: Dictionary = {}
			for dog in waiting:
				var candidates: Array[AnimalController] = dog.wolf_candidates if kind == 0 else dog.stray_candidates
				var best: AnimalController
				var best_score: float = INF
				for animal in candidates:
					if claimed.has(animal):
						continue
					var score := dog.global_position.distance_squared_to(dog.task_point(animal)) if kind == 0 else -dog.protection_center.distance_squared_to(animal.global_position)
					if score < best_score or (is_equal_approx(score, best_score) and best != null and animal.entity_id < best.entity_id):
						best = animal
						best_score = score
				if best == null:
					continue
				var previous: SheepdogController = proposals.get(best)
				var distance := dog.global_position.distance_squared_to(dog.task_point(best))
				var previous_distance := previous.global_position.distance_squared_to(previous.task_point(best)) if previous != null else INF
				if distance < previous_distance or (is_equal_approx(distance, previous_distance) and previous != null and dog.entity_id < previous.entity_id):
					proposals[best] = dog
			if proposals.is_empty():
				break
			for animal: AnimalController in proposals:
				var dog: SheepdogController = proposals[animal]
				assignments[dog][kind] = animal
				claimed[animal] = dog
				waiting.erase(dog)
	for dog: SheepdogController in assignments:
		dog.apply_assignment(assignments[dog][0], assignments[dog][1])

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
	g_gameplayEngine.debug_service.clear_invalid_selection()
	return true

func remove_expired() -> void:
	for index in range(entities.size() - 1, -1, -1):
		var animal: AnimalController = entities[index]
		if not animal.alive and animal.death_remaining <= 0.0:
			entities.remove_at(index)
			match animal.kind:
				AnimalController.Kind.SHEEP:
					sheep.erase(animal)
				AnimalController.Kind.WOLF:
					wolves.erase(animal)
				AnimalController.Kind.SHEEPDOG:
					dogs.erase(animal)
			container.remove_child(animal)
			animal.queue_free()

func clear() -> void:
	for animal in entities:
		container.remove_child(animal)
		animal.queue_free()
	entities.clear()
	sheep.clear()
	wolves.clear()
	dogs.clear()
	_spatial_cells.clear()
	perception_positions.clear()
	perception_velocities.clear()
	perception_kinds.clear()
	reset_spatial_stats()
	next_id = 1
	capture_count = 0
