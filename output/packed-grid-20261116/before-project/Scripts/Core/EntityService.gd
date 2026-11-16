class_name EntityService
extends Service

const SPATIAL_CELL_SIZE: float = 120.0

@export var sheep_scene: PackedScene
@export var wolf_scene: PackedScene
@export var sheepdog_scene: PackedScene

var data := AnimalData.new()
var entities: Array[AnimalEntity] = []
var sheep_rows := PackedInt32Array()
var wolf_rows := PackedInt32Array()
var dog_rows := PackedInt32Array()
var container: Node2D
var next_id: int = 1
var capture_count: int = 0
var _next_uid: int = 0
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
	for row in range(data.row_to_slot.size()):
		data.identity_alive[row] = int(false)
		data.brain_view[row].reset_tree()
		data.brain_view[row].hide()
	data.active_count = 0
	data.retained_count = 0
	_refresh_rows()
	_clear_snapshot()
	next_id = 1
	capture_count = 0

func _shutdown() -> void:
	clear()
	container = null

func spawn(kind: AnimalEntity.Kind, count: int, at_position := Vector2.INF) -> Array[AnimalEntity]:
	var result: Array[AnimalEntity] = []
	var scene: PackedScene = [sheep_scene, wolf_scene, sheepdog_scene][kind]
	if scene == null or not is_instance_valid(container):
		push_error("EntityService requires animal prefabs and an entity container.")
		return result
	for index in range(count):
		var free_row: int = -1
		for candidate in range(data.retained_count, data.row_to_slot.size()):
			if data.identity_kind[candidate] == kind:
				free_row = candidate
				break
		if free_row < 0:
			free_row = data.append_slot()
			data.identity_kind[free_row] = kind
			var view := scene.instantiate() as AnimalView
			container.add_child(view)
			data.brain_view[free_row] = view
			data.brain_player[free_row] = view.bt_player
		data.swap_rows(free_row, data.retained_count)
		data.swap_rows(data.retained_count, data.active_count)
		var row := data.active_count
		data.active_count += 1
		data.retained_count += 1
		data.brain_view[row].reset_tree()
		data.reset_row(row)
		_next_uid += 1
		data.identity_uid[row] = _next_uid
		if data.handles[row] != null:
			data.handles[row].row = -1
		var animal := AnimalEntity.new()
		animal.slot = data.row_to_slot[row]
		animal.uid = _next_uid
		animal.row = row
		data.handles[row] = animal
		data.brain_view[row].entity = animal
		data.identity_entity_id[row] = next_id
		data.identity_kind[row] = kind
		data.identity_alive[row] = int(true)
		var point: Vector2 = g_gameplayEngine.random_position() if at_position == Vector2.INF else at_position
		data.motion_position[row] = point
		data.motion_movement_goal[row] = point
		data.motion_wander_point[row] = point
		data.motion_facing[row] = Vector2.from_angle(g_gameplayEngine.rng.randf_range(-PI, PI))
		if kind != AnimalEntity.Kind.SHEEP:
			data.brain_current_behavior[row] = AnimalEntity.Behavior.PATROL
		if kind == AnimalEntity.Kind.SHEEPDOG:
			data.dog_protection_center[row] = point
			data.dog_patrol_angle[row] = next_id * 2.399963
		g_gameplayEngine.refresh_animal_config(animal)
		data.brain_player[row].active = true
		data.brain_view[row].show()
		data.brain_view[row].sync()
		next_id += 1
		result.append(animal)
	_refresh_rows()
	return result

func spawn_initial() -> void:
	var settings: SimulationConfig = g_gameplayEngine.config
	var center: Vector2 = settings.arena_size * 0.5
	for index in range(settings.initial_sheep):
		var point := center + Vector2(
			g_gameplayEngine.rng.randf_range(-440.0, 440.0),
			g_gameplayEngine.rng.randf_range(-220.0, 220.0))
		spawn(AnimalEntity.Kind.SHEEP, 1, point)

	for index in range(settings.initial_wolves):
		var point: Vector2 = g_gameplayEngine.random_position()
		if index % 2 == 0:
			point.x = 40.0
		else:
			point.x = settings.arena_size.x - 40.0
		spawn(AnimalEntity.Kind.WOLF, 1, point)

	for index in range(settings.initial_sheepdogs):
		var angle := TAU * float(index) / maxf(1.0, settings.initial_sheepdogs)
		spawn(AnimalEntity.Kind.SHEEPDOG, 1, center + Vector2.from_angle(angle) * 100.0)

func _refresh_rows() -> void:
	entities.clear()
	sheep_rows.clear()
	wolf_rows.clear()
	dog_rows.clear()
	for row in range(data.active_count):
		entities.append(data.handles[row])
		data.memory_perception_ready[row] = int(false)
		match data.identity_kind[row]:
			AnimalEntity.Kind.SHEEP:
				sheep_rows.append(row)
			AnimalEntity.Kind.WOLF:
				wolf_rows.append(row)
			AnimalEntity.Kind.SHEEPDOG:
				dog_rows.append(row)

func get_counts() -> Vector3i:
	var counts := Vector3i.ZERO
	for row in range(data.active_count):
		if data.identity_alive[row]:
			counts[data.identity_kind[row]] += 1
	return counts

func capture(prey: AnimalEntity) -> bool:
	if data.live(prey) == null:
		return false
	var row := prey.row
	if data.identity_kind[row] != AnimalEntity.Kind.SHEEP:
		return false
	data.identity_alive[row] = int(false)
	data.identity_death_remaining[row] = g_gameplayEngine.config.death_duration
	data.brain_view[row].reset_tree()
	data.memory_target[row] = null
	data.motion_velocity[row] = Vector2.ZERO
	data.motion_desired_velocity[row] = Vector2.ZERO
	data.brain_current_behavior[row] = AnimalEntity.Behavior.DEAD
	data.brain_view[row].sync()
	capture_count += 1
	g_gameplayEngine.debug_service.clear_invalid_selection()
	return true

func remove_expired(delta: float = 0.0) -> void:
	var changed := false
	var row := 0
	while row < data.active_count:
		if data.identity_alive[row]:
			row += 1
		else:
			data.active_count -= 1
			data.swap_rows(row, data.active_count)
			changed = true
	row = data.active_count
	while row < data.retained_count:
		data.identity_death_remaining[row] -= delta
		if data.identity_death_remaining[row] <= 0.0:
			data.brain_view[row].hide()
			data.retained_count -= 1
			data.swap_rows(row, data.retained_count)
		else:
			row += 1
	if changed:
		_refresh_rows()

func clear() -> void:
	for view in data.brain_view:
		view.entity = null
		view.queue_free()
	data.clear()
	_refresh_rows()
	_clear_snapshot()
	next_id = 1
	capture_count = 0

func rebuild_spatial_index() -> void:
	reset_spatial_stats()
	_spatial_cells.clear()
	perception_positions.resize(data.active_count)
	perception_velocities.resize(data.active_count)
	perception_kinds.resize(data.active_count)
	for row in range(data.active_count):
		var point := data.motion_position[row]
		perception_positions[row] = point
		perception_velocities[row] = data.motion_velocity[row]
		perception_kinds[row] = data.identity_kind[row]
		var cell := Vector2i((point / SPATIAL_CELL_SIZE).floor())
		if not _spatial_cells.has(cell):
			_spatial_cells[cell] = []
		_spatial_cells[cell].append(row)
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

func _clear_snapshot() -> void:
	_spatial_cells.clear()
	perception_positions.clear()
	perception_velocities.clear()
	perception_kinds.clear()
	reset_spatial_stats()
