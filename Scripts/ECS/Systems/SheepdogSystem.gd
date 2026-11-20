class_name SheepdogSystem
extends RefCounted

var data: AnimalData
var _shared_step: int = -1
var _local_groups: Dictionary = {}
var _protection_offsets := PackedInt32Array()
var _protection_radius: float = -1.0
var _protection_cell_size: float = -1.0

var shared_candidate_groups: int = 0
var shared_group_count: int = 0
var shared_group_hits: int = 0

func _init(storage: AnimalData) -> void:
	data = storage

func advance_time(delta: float) -> void:
	var animal_identity := data.identity
	var animal_brain := data.brain
	var animal_motion := data.motion
	var animal_memory := data.memory
	var animal_dog := data.dog
	var animal_index := data.index
	var dog_assignment_remaining := animal_dog.assignment_remaining
	var dog_patrol_angle := animal_dog.patrol_angle
	var identity_entity_id := animal_identity.entity_id
	var dog_guard_point := animal_dog.guard_point
	var index_handles := animal_index.handles
	var dog_protection_center := animal_dog.protection_center
	var dog_region := animal_dog.region
	var memory_target := animal_memory.target
	var dog_collected_sheep := animal_dog.collected_sheep
	var dog_returning := animal_dog.returning
	var motion_position := animal_motion.position
	var dog_protected_sheep := animal_dog.protected_sheep
	var brain_current_behavior := animal_brain.current_behavior
	var settings: SheepdogConfig = g_gameplayEngine.config.sheepdog
	var common: AnimalSystem = g_gameplayEngine.animal_system
	for row in g_gameplayEngine.data_service.animals.index.dog_rows:
		dog_assignment_remaining[row] -= delta
		dog_patrol_angle[row] += settings.patrol_angular_speed * delta * (1.0 if identity_entity_id[row] % 2 == 0 else -1.0)
		dog_guard_point[row] = common.clamp_to_arena(index_handles[row], dog_protection_center[row] + Vector2.from_angle(dog_patrol_angle[row]) * settings.guard_distance)

		if dog_region[row] >= 0:
			if g_gameplayEngine.data_service.animals.index.sheep_rows.is_empty():
				dog_region[row] = -1
				memory_target[row] = null
				dog_collected_sheep[row] = null
				dog_returning[row] = 0
				g_gameplayEngine.advance_decision(index_handles[row])
			elif motion_position[row].distance_to(dog_protection_center[row]) > settings.leash_distance:
				dog_returning[row] = 1
		elif data.live(dog_protected_sheep[row]) == null:
			var lost_anchor := dog_protected_sheep[row] != null
			dog_protected_sheep[row] = null
			memory_target[row] = null
			dog_collected_sheep[row] = null
			dog_returning[row] = 0
			if lost_anchor or brain_current_behavior[row] in [AnimalEntity.Behavior.DRIVE, AnimalEntity.Behavior.COLLECT, AnimalEntity.Behavior.RETURN]:
				g_gameplayEngine.advance_decision(index_handles[row])
		elif motion_position[row].distance_to(dog_protection_center[row]) > settings.leash_distance:
			dog_returning[row] = 1

		if dog_returning[row] and motion_position[row].distance_to(dog_guard_point[row]) <= 24.0:
			dog_returning[row] = 0

func assign_tasks() -> void:
	var identity_entity_id := data.identity.entity_id
	var motion_position := data.motion.position
	var wolves_claimed: Dictionary = {}
	var sheep_claimed: Dictionary = {}
	var assignments: Dictionary = {}
	for dog_row in g_gameplayEngine.data_service.animals.index.dog_rows:
		var dog := data.index.handles[dog_row]
		if data.identity.alive[dog.row]:
			assignments[dog] = [null, null]

	# 1) Resolve nearest wolf proposals, then farthest stray proposals.
	for kind in range(2):
		var claimed: Dictionary = wolves_claimed if kind == 0 else sheep_claimed
		var waiting: Array[AnimalEntity] = []
		for dog: AnimalEntity in assignments:
			if assignments[dog][0] == null and not data.dog.returning[dog.row]:
				waiting.append(dog)
		while not waiting.is_empty():
			var proposals: Dictionary = {}
			for dog in waiting:
				var candidates: Array = data.dog.wolf_candidates[dog.row] if kind == 0 else data.dog.stray_candidates[dog.row]
				var best: AnimalEntity
				var best_score: float = INF
				for animal in candidates:
					if claimed.has(animal):
						continue

					var score := motion_position[dog.row].distance_squared_to(task_point(dog, animal)) if kind == 0 else -data.dog.protection_center[dog.row].distance_squared_to(motion_position[animal.row])
					if score < best_score or (is_equal_approx(score, best_score) and best != null and identity_entity_id[animal.row] < identity_entity_id[best.row]):
						best = animal
						best_score = score
				if best == null:
					continue

				var previous: AnimalEntity = proposals.get(best)
				var distance := motion_position[dog.row].distance_squared_to(task_point(dog, best))
				var previous_distance := motion_position[previous.row].distance_squared_to(task_point(previous, best)) if previous != null else INF
				if distance < previous_distance or (is_equal_approx(distance, previous_distance) and previous != null and identity_entity_id[dog.row] < identity_entity_id[previous.row]):
					proposals[best] = dog
			if proposals.is_empty():
				break

			for animal: AnimalEntity in proposals:
				var dog: AnimalEntity = proposals[animal]
				assignments[dog][kind] = animal
				claimed[animal] = dog
				waiting.erase(dog)

	for dog: AnimalEntity in assignments:
		apply_assignment(dog, assignments[dog][0], assignments[dog][1])

func perceive_batch(delta: float) -> void:
	var started_at := Time.get_ticks_usec()
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var jobs: JobService = g_gameplayEngine.job_service
	var rows: PackedInt32Array = g_gameplayEngine.data_service.animals.index.dog_rows
	var settings: SheepdogConfig = g_gameplayEngine.config.sheepdog
	var input: DogAnchorJob = DogAnchorJob.new()
	input.capture_batch(delta)
	var anchors := PackedInt32Array()
	anchors.resize(data.index.active_count)
	anchors.fill(-1)
	var choosing := PackedInt32Array()
	for row in rows:
		data.dog.assignment_remaining[row] -= delta
		var anchor := data.live(data.dog.protected_sheep[row])
		if anchor != null:
			anchors[row] = anchor.row
		if anchor == null or data.dog.assignment_remaining[row] <= 0.0:
			choosing.append(row)

	input.sheep = g_gameplayEngine.data_service.animals.index.sheep_rows
	input.anchors = anchors
	var coverage := PackedInt32Array()
	coverage.resize(data.index.active_count)
	if not choosing.is_empty():
		for sheep_row in input.sheep:
			var count := 0
			for dog_row in rows:
				if anchors[dog_row] >= 0 and data.motion.position[anchors[dog_row]].distance_to(data.motion.position[sheep_row]) < settings.local_flock_radius:
					count += 1
			coverage[sheep_row] = count
	input.coverage = coverage
	var prepared_at := Time.get_ticks_usec()
	jobs.run_batches(&"DogAnchor", choosing, DogAnchorJob, input)
	jobs.record_stage(&"DogAnchor", started_at, prepared_at)

	started_at = Time.get_ticks_usec()
	var groups: Array[DogPerceptionJob.Group] = []
	groups.resize(data.index.active_count)
	for row in rows:
		data.motion.wander_remaining[row] -= delta
		_prepare_perception(data.index.handles[row], delta)
		var anchor := data.live(data.dog.protected_sheep[row])
		if anchor != null and not data.dog.returning[row]:
			var source := _local_group(anchor, true)
			var group: DogPerceptionJob.Group = DogPerceptionJob.Group.new()
			group.wolves = source.wolves
			group.sheep = source.sheep
			groups[row] = group

	var perception: DogPerceptionJob = DogPerceptionJob.new()
	perception.capture_batch(delta)
	perception.groups = groups
	prepared_at = Time.get_ticks_usec()
	jobs.run_batches(&"Dog", rows, DogPerceptionJob, perception)
	jobs.record_stage(&"Dog", started_at, prepared_at)

func perceive(animal: AnimalEntity, delta: float) -> void:
	var dog_assignment_remaining := data.dog.assignment_remaining
	var dog_protected_sheep := data.dog.protected_sheep
	var dog_protection_center := data.dog.protection_center
	var dog_returning := data.dog.returning
	var dog_wolf_candidates := data.dog.wolf_candidates
	var memory_target := data.memory.target
	var motion_position := data.motion.position
	var row := animal.row
	var settings: SheepdogConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.perceive(animal, delta)
	dog_assignment_remaining[row] -= delta
	if not common.is_live(animal, data.live(dog_protected_sheep[row])) or dog_assignment_remaining[row] <= 0.0:
		_choose_protection_anchor(animal)
		dog_assignment_remaining[row] = settings.reassignment_interval

	_prepare_perception(animal, delta)
	dog_wolf_candidates[row].clear()
	data.dog.stray_candidates[row].clear()
	var anchor := data.live(dog_protected_sheep[row])
	if dog_returning[row] or not common.is_live(animal, anchor):
		return

	var group := _local_group(anchor, true)
	for wolf_row in group["wolves"]:
		var wolf := data.index.handles[wolf_row]
		if data.live(wolf) != null and common.can_see(animal, motion_position[wolf_row]):
			dog_wolf_candidates[row].append(wolf)

	var remembered := data.live(memory_target[row])
	if remembered != null and not data.memory.target_visible[row] and data.memory.unseen_elapsed[row] < settings.memory_duration:
		dog_wolf_candidates[row].append(remembered)

	var radius: float = settings.local_flock_radius
	var collected := data.live(data.dog.collected_sheep[row])
	for index in group["sheep"]:
		var sheep := data.index.handles[index]
		var point := data.motion.position[index]
		var distance := dog_protection_center[row].distance_to(point)
		var threshold: float = radius * settings.collect_complete_ratio if sheep == collected else radius
		if motion_position[anchor.row].distance_to(point) <= radius * 2.0 and distance > threshold:
			data.dog.stray_candidates[row].append(sheep)

func _prepare_perception(animal: AnimalEntity, delta: float) -> void:
	var row := animal.row
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var settings: SheepdogConfig = data.settings[row]
	var dog_protection_center := data.dog.protection_center
	var dog_protected_sheep := data.dog.protected_sheep
	var dog_returning := data.dog.returning
	var memory_target := data.memory.target
	var motion_position := data.motion.position

	_update_protection_center(animal)
	data.dog.patrol_angle[row] += settings.patrol_angular_speed * delta * (1.0 if data.identity.entity_id[row] % 2 == 0 else -1.0)
	data.dog.guard_point[row] = common.clamp_to_arena(animal, dog_protection_center[row] + Vector2.from_angle(data.dog.patrol_angle[row]) * settings.guard_distance)
	common.observe_target(animal, delta)
	if not common.is_live(animal, data.live(dog_protected_sheep[row])):
		memory_target[row] = null
		dog_returning[row] = 0
	elif motion_position[row].distance_to(dog_protection_center[row]) > settings.leash_distance:
		dog_returning[row] = 1
	if dog_returning[row] and motion_position[row].distance_to(data.dog.guard_point[row]) <= 24.0:
		dog_returning[row] = 0

func task_point(animal: AnimalEntity, other: AnimalEntity) -> Vector2:
	var row := animal.row
	if other == data.live(data.memory.target[row]) and not data.memory.target_visible[row]:
		return data.memory.last_seen_position[row]
	return data.motion.position[other.row]

func apply_assignment(animal: AnimalEntity, wolf: AnimalEntity, stray: AnimalEntity) -> void:
	var memory_target := data.memory.target
	var row := animal.row
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var lost_wolf: bool = common.is_live(animal, data.live(memory_target[row])) and wolf == null
	if wolf != data.live(memory_target[row]):
		memory_target[row] = wolf
		common.observe_target(animal, 0.0)

	data.dog.collected_sheep[row] = stray as AnimalEntity
	if lost_wolf:
		data.dog.returning[row] = 1

func _anchor_score(animal: AnimalEntity, sheep: AnimalEntity, anchors: PackedVector2Array) -> float:
	var row := animal.row
	var settings: SheepdogConfig = data.settings[row]
	var point := data.motion.position[sheep.row]
	var coverage: int = 0
	for anchor in anchors:
		if anchor.distance_to(point) < settings.local_flock_radius:
			coverage += 1
	return data.motion.position[row].distance_to(point) / settings.local_flock_radius + coverage * settings.coverage_weight

func _choose_protection_anchor(animal: AnimalEntity) -> void:
	var dog_protected_sheep := data.dog.protected_sheep
	var row := animal.row
	var settings: SheepdogConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
	var anchors := PackedVector2Array()
	for dog_row in g_gameplayEngine.data_service.animals.index.dog_rows:
		var dog := data.index.handles[dog_row]
		var anchor: AnimalEntity = data.live(dog_protected_sheep[dog.row])
		if dog != animal and data.identity.alive[dog.row] and anchor != null:
			anchors.append(data.motion.position[anchor.row])

	var best: AnimalEntity = data.live(dog_protected_sheep[row]) if common.is_live(animal, data.live(dog_protected_sheep[row])) else null
	var current_score: float = _anchor_score(animal, best, anchors) if best != null else INF
	var best_score := current_score
	for sheep_row in g_gameplayEngine.data_service.animals.index.sheep_rows:
		var sheep := data.index.handles[sheep_row]
		if not data.identity.alive[sheep.row]:
			continue

		var score: float = _anchor_score(animal, sheep, anchors)
		if score < best_score:
			best = sheep
			best_score = score

	if not common.is_live(animal, data.live(dog_protected_sheep[row])) or best_score <= current_score * (1.0 - settings.reassignment_improvement):
		dog_protected_sheep[row] = best
	if g_gameplayEngine.profile_service.detailed_stats_enabled:
		g_gameplayEngine.profile_service.record_hotspot("DogAnchor", started)

func _update_protection_center(animal: AnimalEntity) -> void:
	var motion_position := data.motion.position
	var row := animal.row
	var anchor := data.live(data.dog.protected_sheep[row])
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if not common.is_live(animal, anchor):
		data.dog.protection_center[row] = common.get_wander_point(animal, 85.0)
		return

	var group := _local_group(anchor)
	data.dog.protection_center[row] = group["center"] if group["count"] > 0 else motion_position[anchor.row]

func begin_spatial_step() -> void:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	_shared_step = spatial.version
	_local_groups.clear()
	shared_group_count = 0
	shared_group_hits = 0
	shared_candidate_groups = 0

func _local_group(anchor: AnimalEntity, with_candidates: bool = false) -> Dictionary:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	var grid: GridService = g_gameplayEngine.grid_service
	if _shared_step != spatial.version:
		begin_spatial_step()
	var cell := spatial.current.cells.row_cells[anchor.row]
	var settings: SheepdogConfig = g_gameplayEngine.config.sheepdog
	var radius := settings.local_flock_radius
	var center := Vector2(cell % spatial.current.width + 0.5, floorf(float(cell) / spatial.current.width) + 0.5) * spatial.current.cell_size
	var group: Dictionary
	if _local_groups.has(cell):
		group = _local_groups[cell]
		if not with_candidates:
			shared_group_hits += 1
	else:
		if _protection_radius != radius or _protection_cell_size != spatial.current.cell_size:
			_protection_offsets = GridSnapshot.snapshot_offsets(radius, spatial.current.cell_size)
			_protection_radius = radius
			_protection_cell_size = spatial.current.cell_size
		var sum := Vector2.ZERO
		var count := 0
		var cells := PackedInt32Array()
		var x := cell % spatial.current.width
		var y := floori(float(cell) / spatial.current.width)
		for offset in range(0, _protection_offsets.size(), 2):
			var nx := x + _protection_offsets[offset]
			var ny := y + _protection_offsets[offset + 1]
			if nx < 0 or nx >= spatial.current.width or ny < 0 or ny >= spatial.current.height:
				continue

			var neighbor := ny * spatial.current.width + nx
			sum += spatial.current.flock.position_sums[neighbor]
			count += spatial.current.cells.counts[neighbor * 3 + AnimalEntity.Kind.SHEEP]
			if spatial.current.cells.counts[neighbor * 3 + AnimalEntity.Kind.SHEEP] > 0:
				cells.append(neighbor)
		group = {"center": sum / count if count > 0 else center, "count": count, "cells": cells, "ready": false}
		_local_groups[cell] = group
		shared_group_count += 1

	if not with_candidates or group.ready:
		return group

	# 1) Build target candidates only for dogs that are actively choosing a task.
	var flock := PackedInt32Array()
	for neighbor in group.cells:
		var bucket: int = neighbor * 3 + AnimalEntity.Kind.SHEEP
		for member in range(spatial.current.cells.offsets[bucket], spatial.current.cells.offsets[bucket + 1]):
			flock.append(spatial.current.cells.members[member])

	var padding := spatial.current.cell_size * sqrt(0.5)
	var threat_radius_squared := pow(radius + padding + settings.threat_distance, 2)
	var wolves := PackedInt32Array()
	for row in g_gameplayEngine.data_service.animals.index.wolf_rows:
		var threatening: bool = data.wolf.hunting[row] != 0
		if not threatening:
			var point := spatial.current.cells.positions[row]
			if center.distance_squared_to(point) > threat_radius_squared:
				continue

			for sheep_row in flock:
				if point.distance_squared_to(spatial.current.cells.positions[sheep_row]) < settings.threat_distance * settings.threat_distance:
					threatening = true
					break

		if threatening:
			wolves.append(row)

	group.wolves = wolves
	group.sheep = grid.get_nearby_indices(center, radius * 2.0 + padding, AnimalEntity.Kind.SHEEP)
	group.ready = true
	shared_candidate_groups += 1
	return group

func prepare_motion_goals() -> void:
	var animal_brain := data.brain
	var animal_index := data.index
	var animal_motion := data.motion
	var animal_dog := data.dog
	var settings: SheepdogConfig = g_gameplayEngine.config.sheepdog
	var common: AnimalSystem = g_gameplayEngine.animal_system
	for row in g_gameplayEngine.data_service.animals.index.dog_rows:
		if animal_motion.intent[row] != AnimalData.MotionIntent.POINT:
			continue

		match animal_brain.current_behavior[row]:
			AnimalEntity.Behavior.COLLECT:
				var collected := data.live(animal_dog.collected_sheep[row])
				if collected == null:
					continue

				var point := animal_motion.position[collected.row]
				var away := (point - animal_dog.protection_center[row]).normalized()
				animal_motion.movement_goal[row] = common.clamp_to_arena(animal_index.handles[row], point + away * settings.collect_distance)
			AnimalEntity.Behavior.RETURN:
				animal_motion.movement_goal[row] = animal_dog.guard_point[row]
			AnimalEntity.Behavior.PATROL:
				if animal_dog.region[row] >= 0 or data.live(animal_dog.protected_sheep[row]) != null:
					animal_motion.movement_goal[row] = animal_dog.guard_point[row]

func get_debug_details(animal: AnimalEntity) -> String:
	var row := animal.row
	var stray := data.live(data.dog.collected_sheep[row])
	return "Region %d | Stray #%d | Unseen %.1f s" % [data.dog.region[row], data.identity.entity_id[stray.row] if stray != null else 0, data.memory.unseen_elapsed[row]]
