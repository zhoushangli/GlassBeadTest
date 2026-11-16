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

func accumulate_sheep_pressure() -> void:
	g_gameplayEngine.grid_service.accumulate_pressure(AnimalEntity.Kind.SHEEPDOG)

func assign_tasks() -> void:
	var identity_entity_id := data.identity_entity_id
	var motion_position := data.motion_position
	var wolves_claimed: Dictionary = {}
	var sheep_claimed: Dictionary = {}
	var assignments: Dictionary = {}
	for dog_row in g_gameplayEngine.entity_service.dog_rows:
		var dog := data.handles[dog_row]
		if data.identity_alive[dog.row]:
			assignments[dog] = [null, null]

	# 1) Resolve nearest wolf proposals, then farthest stray proposals.
	for kind in range(2):
		var claimed: Dictionary = wolves_claimed if kind == 0 else sheep_claimed
		var waiting: Array[AnimalEntity] = []
		for dog: AnimalEntity in assignments:
			if assignments[dog][0] == null and not data.dog_returning[dog.row]:
				waiting.append(dog)
		while not waiting.is_empty():
			var proposals: Dictionary = {}
			for dog in waiting:
				var candidates: Array = data.dog_wolf_candidates[dog.row] if kind == 0 else data.dog_stray_candidates[dog.row]
				var best: AnimalEntity
				var best_score: float = INF
				for animal in candidates:
					if claimed.has(animal):
						continue

					var score := motion_position[dog.row].distance_squared_to(task_point(dog, animal)) if kind == 0 else -data.dog_protection_center[dog.row].distance_squared_to(motion_position[animal.row])
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
	var rows: PackedInt32Array = g_gameplayEngine.entity_service.dog_rows
	var settings: SheepdogConfig = g_gameplayEngine.config.sheepdog
	var context := common.perception_context(delta)
	var anchors := PackedInt32Array()
	anchors.resize(data.active_count)
	anchors.fill(-1)
	var choosing := PackedInt32Array()
	for row in rows:
		data.dog_assignment_remaining[row] -= delta
		var anchor := data.live(data.dog_protected_sheep[row])
		if anchor != null:
			anchors[row] = anchor.row
		if anchor == null or data.dog_assignment_remaining[row] <= 0.0:
			choosing.append(row)

	context.merge({"common": common, "dogs": rows, "sheep": g_gameplayEngine.entity_service.sheep_rows,
		"anchors": anchors, "radius": settings.local_flock_radius, "coverage_weight": settings.coverage_weight,
		"improvement": settings.reassignment_improvement, "complete_ratio": settings.collect_complete_ratio,
		"memory_duration": settings.memory_duration})
	var coverage := PackedInt32Array()
	coverage.resize(data.active_count)
	if not choosing.is_empty():
		for sheep_row in context.sheep:
			var count := 0
			for dog_row in rows:
				if anchors[dog_row] >= 0 and data.motion_position[anchors[dog_row]].distance_to(data.motion_position[sheep_row]) < settings.local_flock_radius:
					count += 1
			coverage[sheep_row] = count
	context.coverage = coverage
	var prepared_at := Time.get_ticks_usec()
	jobs.run_batches(&"DogAnchor", choosing, DogAnchorJob, context, self)
	jobs.record_stage(&"DogAnchor", started_at, prepared_at)

	started_at = Time.get_ticks_usec()
	var groups: Dictionary = {}
	for row in rows:
		data.motion_wander_remaining[row] -= delta
		_prepare_perception(data.handles[row], delta)
		var anchor := data.live(data.dog_protected_sheep[row])
		if anchor != null and not data.dog_returning[row]:
			groups[row] = _local_group(anchor, true)

	context.groups = groups
	prepared_at = Time.get_ticks_usec()
	jobs.run_batches(&"Dog", rows, DogPerceptionJob, context, self)
	jobs.record_stage(&"Dog", started_at, prepared_at)

func apply_anchors(output: Dictionary) -> void:
	g_gameplayEngine.animal_system.submit_stats(output.stats)
	for result: Dictionary in output.entries:
		data.dog_protected_sheep[result.row] = data.handles[result.anchor] if result.anchor >= 0 else null
		data.dog_assignment_remaining[result.row] = g_gameplayEngine.config.sheepdog.reassignment_interval

func apply_batch(output: Dictionary, delta: float) -> void:
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.submit_stats(output.stats)
	for result: Dictionary in output.entries:
		var row: int = result.row
		common.submit_perception(result, delta, false)
		data.dog_wolf_candidates[row].clear()
		data.dog_stray_candidates[row].clear()
		for candidate in result.wolves:
			data.dog_wolf_candidates[row].append(data.handles[candidate])
		for candidate in result.strays:
			data.dog_stray_candidates[row].append(data.handles[candidate])

func calculate_anchors(output: Dictionary, rows: PackedInt32Array, context: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	var stats := AnimalSystem.batch_stats(context)
	var positions: PackedVector2Array = context.grid.positions
	var coverage: PackedInt32Array = context.coverage
	var radius: float = context.radius
	var weight: float = context.coverage_weight
	for row in rows:
		var current: int = context.anchors[row]
		var started_at := Time.get_ticks_usec() if stats.detailed else 0
		var own_anchor := positions[current] if current >= 0 else Vector2.INF
		var point := positions[row]
		var best := current
		var current_score := _snapshot_anchor_score(point, positions[current], coverage[current], own_anchor, radius, weight) if current >= 0 else INF
		var best_score := current_score
		for sheep_row in context.sheep:
			var score := _snapshot_anchor_score(point, positions[sheep_row], coverage[sheep_row], own_anchor, radius, weight)
			if score < best_score:
				best = sheep_row
				best_score = score
		entries.append({"row": row, "anchor": best if current < 0 or best_score <= current_score * (1.0 - context.improvement) else current})
		if stats.detailed:
			stats.hotspots.DogAnchor += (Time.get_ticks_usec() - started_at) / 1000.0
			stats.calls.DogAnchor += 1
	output.entries = entries
	output.stats = stats

static func _snapshot_anchor_score(point: Vector2, sheep_point: Vector2, coverage: int, own_anchor: Vector2, radius: float, weight: float) -> float:
	if own_anchor.distance_to(sheep_point) < radius:
		coverage -= 1
	return point.distance_to(sheep_point) / radius + coverage * weight

func calculate_batch(output: Dictionary, rows: PackedInt32Array, context: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	var stats := AnimalSystem.batch_stats(context)
	var common: AnimalSystem = context.common
	for row in rows:
		var result := common.calculate_perception(row, context, stats)
		var wolves := PackedInt32Array()
		var strays := PackedInt32Array()
		if context.groups.has(row):
			var group: Dictionary = context.groups[row]
			for wolf_row in group.wolves:
				if common.can_see(data.handles[row], data.motion_position[wolf_row]):
					wolves.append(wolf_row)

			var remembered := data.live(data.memory_target[row])
			if remembered != null and not data.memory_target_visible[row] and data.memory_unseen_elapsed[row] < context.memory_duration:
				wolves.append(remembered.row)

			var anchor := data.live(data.dog_protected_sheep[row])
			var collected := data.live(data.dog_collected_sheep[row])
			for sheep_row in group.sheep:
				var point := data.motion_position[sheep_row]
				var distance := data.dog_protection_center[row].distance_to(point)
				var threshold: float = context.radius * context.complete_ratio if collected != null and sheep_row == collected.row else context.radius
				if data.motion_position[anchor.row].distance_to(point) <= context.radius * 2.0 and distance > threshold:
					strays.append(sheep_row)

		result.wolves = wolves
		result.strays = strays
		entries.append(result)

	output.entries = entries
	output.stats = stats

func perceive(animal: AnimalEntity, delta: float) -> void:
	var dog_assignment_remaining := data.dog_assignment_remaining
	var dog_protected_sheep := data.dog_protected_sheep
	var dog_protection_center := data.dog_protection_center
	var dog_returning := data.dog_returning
	var dog_wolf_candidates := data.dog_wolf_candidates
	var memory_target := data.memory_target
	var motion_position := data.motion_position
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
	data.dog_stray_candidates[row].clear()
	var anchor := data.live(dog_protected_sheep[row])
	if dog_returning[row] or not common.is_live(animal, anchor):
		return

	var group := _local_group(anchor, true)
	for wolf_row in group["wolves"]:
		var wolf := data.handles[wolf_row]
		if data.live(wolf) != null and common.can_see(animal, motion_position[wolf_row]):
			dog_wolf_candidates[row].append(wolf)

	var remembered := data.live(memory_target[row])
	if remembered != null and not data.memory_target_visible[row] and data.memory_unseen_elapsed[row] < settings.memory_duration:
		dog_wolf_candidates[row].append(remembered)

	var radius: float = settings.local_flock_radius
	var collected := data.live(data.dog_collected_sheep[row])
	for index in group["sheep"]:
		var sheep := data.handles[index]
		var point := data.motion_position[index]
		var distance := dog_protection_center[row].distance_to(point)
		var threshold: float = radius * settings.collect_complete_ratio if sheep == collected else radius
		if motion_position[anchor.row].distance_to(point) <= radius * 2.0 and distance > threshold:
			data.dog_stray_candidates[row].append(sheep)

func _prepare_perception(animal: AnimalEntity, delta: float) -> void:
	var row := animal.row
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var settings: SheepdogConfig = data.settings[row]
	var dog_protection_center := data.dog_protection_center
	var dog_protected_sheep := data.dog_protected_sheep
	var dog_returning := data.dog_returning
	var memory_target := data.memory_target
	var motion_position := data.motion_position

	_update_protection_center(animal)
	data.dog_patrol_angle[row] += settings.patrol_angular_speed * delta * (1.0 if data.identity_entity_id[row] % 2 == 0 else -1.0)
	data.dog_guard_point[row] = common.clamp_to_arena(animal, dog_protection_center[row] + Vector2.from_angle(data.dog_patrol_angle[row]) * settings.guard_distance)
	common.observe_target(animal, delta)
	if not common.is_live(animal, data.live(dog_protected_sheep[row])):
		memory_target[row] = null
		dog_returning[row] = 0
	elif motion_position[row].distance_to(dog_protection_center[row]) > settings.leash_distance:
		dog_returning[row] = 1
	if dog_returning[row] and motion_position[row].distance_to(data.dog_guard_point[row]) <= 24.0:
		dog_returning[row] = 0

func task_point(animal: AnimalEntity, other: AnimalEntity) -> Vector2:
	var row := animal.row
	if other == data.live(data.memory_target[row]) and not data.memory_target_visible[row]:
		return data.memory_last_seen_position[row]
	return data.motion_position[other.row]

func apply_assignment(animal: AnimalEntity, wolf: AnimalEntity, stray: AnimalEntity) -> void:
	var memory_target := data.memory_target
	var row := animal.row
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var lost_wolf: bool = common.is_live(animal, data.live(memory_target[row])) and wolf == null
	if wolf != data.live(memory_target[row]):
		memory_target[row] = wolf
		common.observe_target(animal, 0.0)
	data.dog_collected_sheep[row] = stray as AnimalEntity
	if lost_wolf:
		data.dog_returning[row] = 1

func _anchor_score(animal: AnimalEntity, sheep: AnimalEntity, anchors: PackedVector2Array) -> float:
	var row := animal.row
	var settings: SheepdogConfig = data.settings[row]
	var point := data.motion_position[sheep.row]
	var coverage: int = 0
	for anchor in anchors:
		if anchor.distance_to(point) < settings.local_flock_radius:
			coverage += 1
	return data.motion_position[row].distance_to(point) / settings.local_flock_radius + coverage * settings.coverage_weight

func _choose_protection_anchor(animal: AnimalEntity) -> void:
	var dog_protected_sheep := data.dog_protected_sheep
	var row := animal.row
	var settings: SheepdogConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
	var anchors := PackedVector2Array()
	for dog_row in g_gameplayEngine.entity_service.dog_rows:
		var dog := data.handles[dog_row]
		var anchor: AnimalEntity = data.live(dog_protected_sheep[dog.row])
		if dog != animal and data.identity_alive[dog.row] and anchor != null:
			anchors.append(data.motion_position[anchor.row])

	var best: AnimalEntity = data.live(dog_protected_sheep[row]) if common.is_live(animal, data.live(dog_protected_sheep[row])) else null
	var current_score: float = _anchor_score(animal, best, anchors) if best != null else INF
	var best_score := current_score
	for sheep_row in g_gameplayEngine.entity_service.sheep_rows:
		var sheep := data.handles[sheep_row]
		if not data.identity_alive[sheep.row]:
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
	var motion_position := data.motion_position
	var row := animal.row
	var anchor := data.live(data.dog_protected_sheep[row])
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if not common.is_live(animal, anchor):
		data.dog_protection_center[row] = common.get_wander_point(animal, 85.0)
		return

	var group := _local_group(anchor)
	data.dog_protection_center[row] = group["center"] if group["count"] > 0 else motion_position[anchor.row]

func begin_spatial_step() -> void:
	_shared_step = g_gameplayEngine.grid_service.snapshot_version
	_local_groups.clear()
	shared_group_count = 0
	shared_group_hits = 0
	shared_candidate_groups = 0

func _local_group(anchor: AnimalEntity, with_candidates: bool = false) -> Dictionary:
	var grid: GridService = g_gameplayEngine.grid_service
	if _shared_step != grid.snapshot_version:
		begin_spatial_step()
	var cell := grid.row_cells[anchor.row]
	var settings: SheepdogConfig = g_gameplayEngine.config.sheepdog
	var radius := settings.local_flock_radius
	var center := Vector2(cell % grid.width + 0.5, floorf(float(cell) / grid.width) + 0.5) * grid.cell_size
	var group: Dictionary
	if _local_groups.has(cell):
		group = _local_groups[cell]
		if not with_candidates:
			shared_group_hits += 1
	else:
		if _protection_radius != radius or _protection_cell_size != grid.cell_size:
			_protection_offsets = grid._make_offsets(radius)
			_protection_radius = radius
			_protection_cell_size = grid.cell_size
		var sum := Vector2.ZERO
		var count := 0
		var cells := PackedInt32Array()
		var x := cell % grid.width
		var y := floori(float(cell) / grid.width)
		for offset in range(0, _protection_offsets.size(), 2):
			var nx := x + _protection_offsets[offset]
			var ny := y + _protection_offsets[offset + 1]
			if nx < 0 or nx >= grid.width or ny < 0 or ny >= grid.height:
				continue

			var neighbor := ny * grid.width + nx
			sum += grid.sheep_position_sums[neighbor]
			count += grid.cell_counts[neighbor * 3 + AnimalEntity.Kind.SHEEP]
			if grid.cell_counts[neighbor * 3 + AnimalEntity.Kind.SHEEP] > 0:
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
		for member in range(grid.cell_offsets[bucket], grid.cell_offsets[bucket + 1]):
			flock.append(grid.members[member])

	var padding := grid.cell_size * sqrt(0.5)
	var threat_radius_squared := pow(radius + padding + settings.threat_distance, 2)
	var wolves := PackedInt32Array()
	for row in g_gameplayEngine.entity_service.wolf_rows:
		var threatening: bool = data.wolf_hunting[row] != 0
		if not threatening:
			var point := grid.perception_positions[row]
			if center.distance_squared_to(point) > threat_radius_squared:
				continue

			for sheep_row in flock:
				if point.distance_squared_to(grid.perception_positions[sheep_row]) < settings.threat_distance * settings.threat_distance:
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
	var settings: SheepdogConfig = g_gameplayEngine.config.sheepdog
	var common: AnimalSystem = g_gameplayEngine.animal_system
	for row in g_gameplayEngine.entity_service.dog_rows:
		if data.motion_intent[row] == AnimalData.MotionIntent.POINT and data.brain_current_behavior[row] == AnimalEntity.Behavior.COLLECT:
			var point := data.motion_movement_goal[row]
			var away := (point - data.dog_protection_center[row]).normalized()
			data.motion_movement_goal[row] = common.clamp_to_arena(data.handles[row], point + away * settings.collect_distance)

func get_debug_details(animal: AnimalEntity) -> String:
	var row := animal.row
	var common: AnimalSystem = g_gameplayEngine.animal_system
	return "Anchor #%d | Stray #%d | Unseen %.1f s" % [data.identity_entity_id[data.live(data.dog_protected_sheep[row]).row] if common.is_live(animal, data.live(data.dog_protected_sheep[row])) else 0, data.identity_entity_id[data.live(data.dog_collected_sheep[row]).row] if common.is_live(animal, data.live(data.dog_collected_sheep[row])) else 0, data.memory_unseen_elapsed[row]]
