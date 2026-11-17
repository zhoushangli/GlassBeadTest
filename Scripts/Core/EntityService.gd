class_name EntityService
extends Service

@export var wolf_behavior_tree: BehaviorTree
@export var sheepdog_behavior_tree: BehaviorTree

var data := AnimalData.new()
var entities: Array[AnimalEntity] = []
var sheep_rows := PackedInt32Array()
var wolf_rows := PackedInt32Array()
var dog_rows := PackedInt32Array()

var container: Node2D
var next_id: int = 1
var capture_count: int = 0

var _next_uid: int = 0

func _reset() -> void:
	for row in range(data.row_to_slot.size()):
		data.identity_alive[row] = int(false)
		_reset_brain(row)

	data.active_count = 0
	data.retained_count = 0
	_refresh_rows()
	g_gameplayEngine.grid_service.reset()
	g_gameplayEngine.render_service.mark_dirty()
	next_id = 1
	capture_count = 0

func _shutdown() -> void:
	clear()
	container = null

func spawn(kind: AnimalEntity.Kind, count: int, at_position := Vector2.INF) -> Array[AnimalEntity]:
	var result: Array[AnimalEntity] = []
	if count > AnimalID.PART_MASK - _next_uid:
		push_error("AnimalID life serial exhausted; spawn request rejected without wrapping.")
		return result

	var tree: BehaviorTree = [null, wolf_behavior_tree, sheepdog_behavior_tree][kind]
	if (kind != AnimalEntity.Kind.SHEEP and (tree == null or tree.root_task == null)) or not is_instance_valid(container):
		push_error("EntityService requires valid behavior trees and an entity container.")
		return result

	# 1) Reuse same-species storage and keep active rows before retained corpses.
	for index in range(count):
		var free_row: int = -1
		for candidate in range(data.retained_count, data.row_to_slot.size()):
			if data.identity_kind[candidate] == kind:
				free_row = candidate
				break

		if free_row < 0:
			free_row = data.append_slot()
			data.identity_kind[free_row] = kind

		data.swap_rows(free_row, data.retained_count)
		data.swap_rows(data.retained_count, data.active_count)
		var row := data.active_count
		data.active_count += 1
		data.retained_count += 1
		_reset_brain(row)
		data.reset_row(row)

		# 1) Assign a new life identity even when reusing the same slot.
		_next_uid += 1
		data.identity_animal_id[row] = AnimalID.make(data.row_to_slot[row], _next_uid)
		if data.handles[row] != null:
			data.handles[row].row = -1
		var animal := AnimalEntity.new()
		animal.id = data.identity_animal_id[row]
		animal.row = row
		data.handles[row] = animal
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
		if tree != null and not _bind_brain(row, tree):
			data.identity_alive[row] = 0
			animal.row = -1
			data.handles[row] = null
			data.active_count -= 1
			data.retained_count -= 1
			data.swap_rows(row, data.retained_count)
			break

		next_id += 1
		result.append(animal)

	# 2) Refresh row lists once after the spawn batch.
	_refresh_rows()
	g_gameplayEngine.render_service.mark_dirty()
	return result

func _reset_brain(row: int) -> void:
	var instance := data.brain_instance[row]
	if instance == null:
		return

	instance.get_root_task().abort()
	var board := instance.get_blackboard()
	for key in board.list_vars():
		board.erase_var(key)

func _bind_brain(row: int, tree: BehaviorTree) -> bool:
	# 1) Create an independent tree and blackboard, or rebind a pooled tree to its new handle.
	var instance := data.brain_instance[row]
	if instance == null:
		var board := Blackboard.new()
		board.set_var(&"animal", data.handles[row])
		instance = tree.instantiate(self, board, self, self)
		if instance == null:
			push_error("Unable to instantiate animal behavior tree.")
			return false

		data.brain_instance[row] = instance
		if EngineDebugger.is_active():
			instance.register_with_debugger()
	else:
		var board := instance.get_blackboard()
		board.set_var(&"animal", data.handles[row])
		instance.get_root_task().initialize(self, board, self)

	return true

func spawn_initial() -> void:
	var settings: SimulationConfig = g_gameplayEngine.config
	var counts := settings.get_initial_counts()
	for kind in [AnimalEntity.Kind.SHEEP, AnimalEntity.Kind.WOLF, AnimalEntity.Kind.SHEEPDOG]:
		spawn(kind, counts[kind])

func _refresh_rows() -> void:
	data.structure_version += 1
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

	data.structure_version += 1
	data.identity_alive[row] = int(false)
	data.identity_death_remaining[row] = g_gameplayEngine.config.death_duration
	_reset_brain(row)
	data.memory_target[row] = null
	data.motion_velocity[row] = Vector2.ZERO
	data.motion_desired_velocity[row] = Vector2.ZERO
	data.brain_current_behavior[row] = AnimalEntity.Behavior.DEAD
	g_gameplayEngine.render_service.mark_dirty()
	capture_count += 1
	g_gameplayEngine.debug_service.clear_invalid_selection()
	return true

func remove_expired(delta: float = 0.0) -> void:
	# 1) Move captured animals out of the active prefix without skipping swapped-in rows.
	var changed := false
	var row := 0
	while row < data.active_count:
		if data.identity_alive[row]:
			row += 1
		else:
			data.active_count -= 1
			data.swap_rows(row, data.active_count)
			changed = true

	# 2) Retain corpses for presentation, then return expired rows to the pool.
	row = data.active_count
	while row < data.retained_count:
		data.identity_death_remaining[row] -= delta
		if data.identity_death_remaining[row] <= 0.0:
			g_gameplayEngine.render_service.mark_dirty()
			data.retained_count -= 1
			data.swap_rows(row, data.retained_count)
		else:
			row += 1

	# 3) Rebuild species lists only when the active prefix changed.
	if changed:
		_refresh_rows()

func clear() -> void:
	# Release tree references before storage; tasks retain AnimalData.
	# e.g. clear() breaks data -> instance -> task -> data ownership.
	for row in range(data.brain_instance.size()):
		_reset_brain(row)
		data.brain_instance[row] = null

	g_gameplayEngine.render_service.mark_dirty()
	data.clear()
	_refresh_rows()
	g_gameplayEngine.grid_service.reset()
	g_gameplayEngine.render_service.mark_dirty()
	next_id = 1
	capture_count = 0

func update_movement(delta: float) -> void:
	if not g_gameplayEngine.compute_service.run_movement(data, delta):
		g_gameplayEngine.fail_step("GPU movement failed: " + g_gameplayEngine.compute_service.failure)
