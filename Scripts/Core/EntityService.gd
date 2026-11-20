class_name EntityService
extends Service

@export var wolf_behavior_tree: BehaviorTree
@export var sheepdog_behavior_tree: BehaviorTree

var container: Node2D

func _reset() -> void:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	for row in range(data.index.row_to_slot.size()):
		data.identity.alive[row] = int(false)
		_reset_brain(row)

	data.index.active_count = 0
	data.index.retained_count = 0
	_refresh_rows()
	g_gameplayEngine.grid_service.reset()
	g_gameplayEngine.render_service.mark_dirty()
	data.index.next_id = 1
	data.index.capture_count = 0

func _shutdown() -> void:
	clear()
	container = null

func spawn(kind: AnimalEntity.Kind, count: int, at_position := Vector2.INF) -> Array[AnimalEntity]:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	var result: Array[AnimalEntity] = []
	if count > AnimalID.PART_MASK - data.index.next_uid:
		push_error("AnimalID life serial exhausted; spawn request rejected without wrapping.")
		return result

	var tree: BehaviorTree = [null, wolf_behavior_tree, sheepdog_behavior_tree][kind]
	if (kind != AnimalEntity.Kind.SHEEP and (tree == null or tree.root_task == null)) or not is_instance_valid(container):
		push_error("EntityService requires valid behavior trees and an entity container.")
		return result

	# 1) Reuse same-species storage and keep active rows before retained corpses.
	for index in range(count):
		var free_row: int = -1
		for candidate in range(data.index.retained_count, data.index.row_to_slot.size()):
			if data.identity.kind[candidate] == kind:
				free_row = candidate
				break

		if free_row < 0:
			free_row = data.append_slot()
			data.identity.kind[free_row] = kind

		data.swap_rows(free_row, data.index.retained_count)
		data.swap_rows(data.index.retained_count, data.index.active_count)
		var row := data.index.active_count
		data.index.active_count += 1
		data.index.retained_count += 1
		_reset_brain(row)
		data.reset_row(row)

		# 1) Assign a new life identity even when reusing the same slot.
		data.index.next_uid += 1
		data.identity.animal_id[row] = AnimalID.make(data.index.row_to_slot[row], data.index.next_uid)
		if data.index.handles[row] != null:
			data.index.handles[row].row = -1
		var animal: AnimalEntity = AnimalEntity.new()
		animal.id = data.identity.animal_id[row]
		animal.row = row
		data.index.handles[row] = animal
		data.identity.entity_id[row] = data.index.next_id
		data.identity.kind[row] = kind
		data.identity.alive[row] = int(true)

		var point: Vector2 = g_gameplayEngine.random_position() if at_position == Vector2.INF else at_position
		data.motion.position[row] = point
		data.motion.movement_goal[row] = point
		data.motion.wander_point[row] = point
		data.motion.facing[row] = Vector2.from_angle(g_gameplayEngine.rng.randf_range(-PI, PI))
		if kind != AnimalEntity.Kind.SHEEP:
			data.brain.current_behavior[row] = AnimalEntity.Behavior.PATROL
		if kind == AnimalEntity.Kind.SHEEPDOG:
			data.dog.protection_center[row] = point
			data.dog.patrol_angle[row] = data.index.next_id * 2.399963

		g_gameplayEngine.refresh_animal_config(animal)
		if tree != null and not _bind_brain(row, tree):
			data.identity.alive[row] = 0
			animal.row = -1
			data.index.handles[row] = null
			data.index.active_count -= 1
			data.index.retained_count -= 1
			data.swap_rows(row, data.index.retained_count)
			break

		data.index.next_id += 1
		result.append(animal)

	# 2) Refresh row lists once after the spawn batch.
	_refresh_rows()
	g_gameplayEngine.render_service.mark_dirty()
	return result

func _reset_brain(row: int) -> void:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	var instance := data.brain.instance[row]
	if instance == null:
		return

	instance.get_root_task().abort()
	var board := instance.get_blackboard()
	for key in board.list_vars():
		board.erase_var(key)

func _bind_brain(row: int, tree: BehaviorTree) -> bool:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	# 1) Create an independent tree and blackboard, or rebind a pooled tree to its new handle.
	var instance := data.brain.instance[row]
	if instance == null:
		var board: Blackboard = Blackboard.new()
		board.set_var(&"animal", data.index.handles[row])
		instance = tree.instantiate(self, board, self, self)
		if instance == null:
			push_error("Unable to instantiate animal behavior tree.")
			return false

		data.brain.instance[row] = instance
		if EngineDebugger.is_active():
			instance.register_with_debugger()
	else:
		var board := instance.get_blackboard()
		board.set_var(&"animal", data.index.handles[row])
		instance.get_root_task().initialize(self, board, self)

	return true

func spawn_initial() -> void:
	var settings: SimulationConfig = g_gameplayEngine.config
	var counts := settings.get_initial_counts()
	for kind in [AnimalEntity.Kind.SHEEP, AnimalEntity.Kind.WOLF, AnimalEntity.Kind.SHEEPDOG]:
		spawn(kind, counts[kind])

func _refresh_rows() -> void:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	var animal_identity := data.identity
	var animal_memory := data.memory
	var animal_index := data.index
	var index_handles := animal_index.handles
	var memory_perception_ready := animal_memory.perception_ready
	var identity_kind := animal_identity.kind
	animal_index.structure_version += 1
	animal_index.entities.clear()
	animal_index.sheep_rows.clear()
	animal_index.wolf_rows.clear()
	animal_index.dog_rows.clear()
	for row in range(animal_index.active_count):
		animal_index.entities.append(index_handles[row])
		memory_perception_ready[row] = int(false)
		match identity_kind[row]:
			AnimalEntity.Kind.SHEEP:
				animal_index.sheep_rows.append(row)
			AnimalEntity.Kind.WOLF:
				animal_index.wolf_rows.append(row)
			AnimalEntity.Kind.SHEEPDOG:
				animal_index.dog_rows.append(row)

func get_counts() -> Vector3i:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	var animal_index := data.index
	var animal_identity := data.identity
	var counts := Vector3i.ZERO
	for row in range(animal_index.active_count):
		if animal_identity.alive[row]:
			counts[animal_identity.kind[row]] += 1
	return counts

func capture(prey: AnimalEntity) -> bool:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	if data.live(prey) == null:
		return false

	var row := prey.row
	if data.identity.kind[row] != AnimalEntity.Kind.SHEEP:
		return false

	data.index.structure_version += 1
	data.identity.alive[row] = int(false)
	data.identity.death_remaining[row] = g_gameplayEngine.config.death_duration
	_reset_brain(row)
	data.memory.target[row] = null
	data.motion.velocity[row] = Vector2.ZERO
	data.motion.desired_velocity[row] = Vector2.ZERO
	data.brain.current_behavior[row] = AnimalEntity.Behavior.DEAD
	g_gameplayEngine.render_service.mark_dirty()
	data.index.capture_count += 1
	g_gameplayEngine.debug_service.clear_invalid_selection()
	return true

func remove_expired(delta: float = 0.0) -> void:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	var animal_identity := data.identity
	var animal_index := data.index
	var identity_alive := animal_identity.alive
	var identity_death_remaining := animal_identity.death_remaining
	# 1) Move captured animals out of the active prefix without skipping swapped-in rows.
	var changed := false
	var row := 0
	while row < animal_index.active_count:
		if identity_alive[row]:
			row += 1
		else:
			animal_index.active_count -= 1
			data.swap_rows(row, animal_index.active_count)
			changed = true

	# 2) Retain corpses for presentation, then return expired rows to the pool.
	row = animal_index.active_count
	while row < animal_index.retained_count:
		identity_death_remaining[row] -= delta
		if identity_death_remaining[row] <= 0.0:
			g_gameplayEngine.render_service.mark_dirty()
			animal_index.retained_count -= 1
			data.swap_rows(row, animal_index.retained_count)
		else:
			row += 1

	# 3) Rebuild species lists only when the active prefix changed.
	if changed:
		_refresh_rows()

func clear() -> void:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	# Release tree references before storage; tasks retain AnimalData.
	# e.g. clear() breaks data -> instance -> task -> data ownership.
	for row in range(data.brain.instance.size()):
		_reset_brain(row)
		data.brain.instance[row] = null

	g_gameplayEngine.render_service.mark_dirty()
	data.clear()
	_refresh_rows()
	g_gameplayEngine.grid_service.reset()
	g_gameplayEngine.render_service.mark_dirty()
	data.index.next_id = 1
	data.index.capture_count = 0

func update_movement(delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.data_service.animals
	var job: NumericComputeJob = NumericComputeJob.new()
	job.capture(data, g_gameplayEngine.config, delta)
	if not job.run():
		g_gameplayEngine.fail_step("GPU movement failed: " + g_gameplayEngine.compute_service.failure)
