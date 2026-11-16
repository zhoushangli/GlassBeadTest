class_name DogPerceptionJob
extends Job

func execute() -> void:
	if context.has("version"):
		_calculate_decision()
		return

	target.calculate_batch(result, rows, context)

func apply_result() -> void:
	if context.has("version"):
		target.apply_decision(result, context)
		return

	target.apply_batch(result, context.delta)

func _calculate_decision() -> void:
	var started := Time.get_ticks_usec()
	var stats := AnimalSystem.batch_stats(context)
	var settings: Dictionary = context.settings
	var radius: float = settings.local_flock_radius
	var anchors: PackedInt32Array = context.dog_protected_sheep.duplicate()
	var coverage := PackedInt32Array()
	coverage.resize(context.motion_position.size())

	# 1) Choose anchors using the previous round's coverage.
	for sheep in context.sheep:
		for dog in rows:
			if anchors[dog] >= 0 and context.motion_position[anchors[dog]].distance_to(context.motion_position[sheep]) < radius:
				coverage[sheep] += 1

	for dog in rows:
		var current: int = anchors[dog]
		if current >= 0 and context.dog_assignment_remaining[dog] > 0.0:
			continue

		var best := current
		var own: Vector2 = context.motion_position[current] if current >= 0 else Vector2.INF
		var current_score := _anchor_score(dog, current, coverage, own) if current >= 0 else INF
		var best_score := current_score
		for sheep in context.sheep:
			var score := _anchor_score(dog, sheep, coverage, own)
			if score < best_score:
				best = sheep
				best_score = score
		if current < 0 or best_score <= current_score * (1.0 - settings.reassignment_improvement):
			anchors[dog] = best

	# 2) Collect perception and shared local-group candidates.
	var entries: Array[Dictionary] = []
	var groups: Dictionary = {}
	for dog in rows:
		var entry := AnimalSystem.snapshot_perception(dog, context, stats)
		entry.anchor = anchors[dog]
		entry.reassigned = context.dog_protected_sheep[dog] < 0 or context.dog_assignment_remaining[dog] <= 0.0
		entry.wolves = PackedInt32Array()
		entry.strays = PackedInt32Array()
		entry.center = context.dog_protection_center[dog]
		entry.returning = bool(context.dog_returning[dog])
		if entry.anchor >= 0:
			var cell: int = context.grid.row_cells[entry.anchor]
			if not groups.has(cell):
				groups[cell] = _local_group(cell, stats)
			var group: Dictionary = groups[cell]
			entry.center = group.center if group.count > 0 else context.motion_position[entry.anchor]
			if context.motion_position[dog].distance_to(entry.center) > settings.leash_distance:
				entry.returning = true
			if not entry.returning:
				for wolf in group.wolves:
					if AnimalSystem.snapshot_can_see(dog, context.motion_position[wolf], context):
						entry.wolves.append(wolf)
				var remembered: int = context.memory_target[dog]
				if remembered >= 0 and not entry.visible and context.memory_unseen_elapsed[dog] < settings.memory_duration and not entry.wolves.has(remembered):
					entry.wolves.append(remembered)
				for sheep in group.sheep:
					var point: Vector2 = context.motion_position[sheep]
					var threshold: float = radius * settings.collect_complete_ratio if sheep == context.dog_collected_sheep[dog] else radius
					if context.motion_position[entry.anchor].distance_to(point) <= radius * 2.0 and entry.center.distance_to(point) > threshold:
						entry.strays.append(sheep)
		entries.append(entry)

	# 3) Resolve exclusive tasks with stable entity-ID tie breaks.
	var wolves_claimed: Dictionary = {}
	var sheep_claimed: Dictionary = {}
	for entry in entries:
		entry.wolf = -1
		entry.stray = -1

	for kind in range(2):
		var claimed: Dictionary = wolves_claimed if kind == 0 else sheep_claimed
		var waiting: Array[Dictionary] = []
		for entry in entries:
			if entry.wolf < 0 and not entry.returning:
				waiting.append(entry)
		while not waiting.is_empty():
			var proposals: Dictionary = {}
			for entry in waiting:
				var best := -1
				var best_score := INF
				for other in (entry.wolves if kind == 0 else entry.strays):
					if claimed.has(other):
						continue

					var score: float = context.motion_position[entry.row].distance_squared_to(_task_point(entry, other)) if kind == 0 else -entry.center.distance_squared_to(context.motion_position[other])
					if score < best_score or (is_equal_approx(score, best_score) and best >= 0 and context.identity_entity_id[other] < context.identity_entity_id[best]):
						best = other
						best_score = score
				if best < 0:
					continue

				var distance: float = context.motion_position[entry.row].distance_squared_to(_task_point(entry, best))
				if not proposals.has(best):
					proposals[best] = entry
				else:
					var previous: Dictionary = proposals[best]
					var previous_distance: float = context.motion_position[previous.row].distance_squared_to(_task_point(previous, best))
					if distance < previous_distance or (is_equal_approx(distance, previous_distance) and context.identity_entity_id[entry.row] < context.identity_entity_id[previous.row]):
						proposals[best] = entry
			if proposals.is_empty():
				break

			for other in proposals:
				var entry: Dictionary = proposals[other]
				entry["wolf" if kind == 0 else "stray"] = other
				claimed[other] = entry.row
				waiting.erase(entry)

	result = {"entries": entries, "stats": stats, "execute_ms": (Time.get_ticks_usec() - started) / 1000.0}

func _task_point(entry: Dictionary, other: int) -> Vector2:
	return entry.last_position if other == entry.target and not entry.visible else context.motion_position[other]

func _anchor_score(dog: int, sheep: int, coverage: PackedInt32Array, own: Vector2) -> float:
	var count := coverage[sheep]
	if own.distance_to(context.motion_position[sheep]) < context.settings.local_flock_radius:
		count -= 1
	return context.motion_position[dog].distance_to(context.motion_position[sheep]) / context.settings.local_flock_radius + count * context.settings.coverage_weight

func _local_group(cell: int, stats: Dictionary) -> Dictionary:
	var grid: Dictionary = context.grid
	var size: float = grid.cell_size
	var radius: float = context.settings.local_flock_radius
	var center := Vector2(cell % grid.width + 0.5, floorf(float(cell) / grid.width) + 0.5) * size
	var sum := Vector2.ZERO
	var count := 0
	var flock := PackedInt32Array()
	var extent := ceili(radius / size)
	var x := cell % int(grid.width)
	var y := floori(float(cell) / grid.width)
	for dy in range(-extent, extent + 1):
		for dx in range(-extent, extent + 1):
			if Vector2(dx, dy).length_squared() * size * size > radius * radius or x + dx < 0 or x + dx >= grid.width or y + dy < 0 or y + dy >= grid.height:
				continue

			var neighbor: int = (y + dy) * grid.width + x + dx
			sum += context.sheep_position_sums[neighbor]
			count += context.cell_counts[neighbor * 3 + AnimalEntity.Kind.SHEEP]
			var bucket := neighbor * 3 + AnimalEntity.Kind.SHEEP
			for member in range(grid.offsets[bucket], grid.offsets[bucket + 1]):
				flock.append(grid.members[member])
	var wolves := PackedInt32Array()
	var threat_squared: float = pow(radius + size * sqrt(0.5) + context.settings.threat_distance, 2)
	for wolf in context.wolves:
		var threatening: bool = context.wolf_hunting[wolf] != 0
		if not threatening and center.distance_squared_to(context.motion_position[wolf]) <= threat_squared:
			for sheep in flock:
				if context.motion_position[wolf].distance_squared_to(context.motion_position[sheep]) < pow(context.settings.threat_distance, 2):
					threatening = true
					break
		if threatening:
			wolves.append(wolf)
	return {"center": sum / count if count > 0 else center, "count": count, "wolves": wolves,
		"sheep": GridService.query_snapshot(center, radius * 2.0 + size * sqrt(0.5), AnimalEntity.Kind.SHEEP, grid, stats)}
