class_name DogPerceptionJob
extends Job

var separations := PackedVector2Array()
var refresh_flags := PackedByteArray()
var remaining := PackedFloat64Array()
var target_rows := PackedInt32Array()
var visible_flags := PackedByteArray()
var last_positions := PackedVector2Array()
var last_velocities := PackedVector2Array()

var anchor_rows := PackedInt32Array()
var centers := PackedVector2Array()
var reassigned_flags := PackedByteArray()
var returning_flags := PackedByteArray()
var wolf_rows := PackedInt32Array()
var stray_rows := PackedInt32Array()

var nearby_offsets := PackedInt32Array()
var nearby_members := PackedInt32Array()

var wolf_offsets := PackedInt32Array()
var wolves := PackedInt32Array()
var stray_offsets := PackedInt32Array()
var strays := PackedInt32Array()

func execute() -> void:
	if context.has("version"):
		_calculate_decision()
		return

	target.calculate_batch(self)

func apply_result() -> void:
	if context.has("version"):
		target.apply_decision(self)
		return

	target.apply_batch(self)

func _calculate_decision() -> void:
	var started := Time.get_ticks_usec()
	resize_output()
	stats = AnimalSystem.batch_stats(context)
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
	var groups: Dictionary = {}
	for index in range(rows.size()):
		var dog := rows[index]
		refresh_flags[index] = int(not context.memory_perception_ready[dog] or context.memory_perception_remaining[dog] <= 0.0)
		separations[index] = AnimalSystem.snapshot_separation(dog, context, stats, bool(refresh_flags[index]))
		target_rows[index] = context.memory_target[dog]
		var target_row := target_rows[index]
		var visible := target_row >= 0 and AnimalSystem.snapshot_can_see(dog, context.motion_position[target_row], context)
		visible_flags[index] = int(visible)
		last_positions[index] = context.motion_position[target_row] if visible else context.memory_last_seen_position[dog]
		last_velocities[index] = context.motion_velocity[target_row] if visible else context.memory_last_seen_velocity[dog]
		anchor_rows[index] = anchors[dog]
		reassigned_flags[index] = int(context.dog_protected_sheep[dog] < 0 or context.dog_assignment_remaining[dog] <= 0.0)
		centers[index] = context.dog_protection_center[dog]
		returning_flags[index] = context.dog_returning[dog]
		if anchor_rows[index] >= 0:
			var cell: int = context.grid.row_cells[anchor_rows[index]]
			if not groups.has(cell):
				groups[cell] = _local_group(cell, stats)
			var group: Dictionary = groups[cell]
			centers[index] = group.center if group.count > 0 else context.motion_position[anchor_rows[index]]
			if context.motion_position[dog].distance_to(centers[index]) > settings.leash_distance:
				returning_flags[index] = 1
			if not returning_flags[index]:
				for wolf in group.wolves:
					if AnimalSystem.snapshot_can_see(dog, context.motion_position[wolf], context):
						wolves.append(wolf)
				var remembered: int = context.memory_target[dog]
				if remembered >= 0 and not visible_flags[index] and context.memory_unseen_elapsed[dog] < settings.memory_duration and not wolves.slice(wolf_offsets[index], wolves.size()).has(remembered):
					wolves.append(remembered)
				for sheep in group.sheep:
					var point: Vector2 = context.motion_position[sheep]
					var threshold: float = radius * settings.collect_complete_ratio if sheep == context.dog_collected_sheep[dog] else radius
					if context.motion_position[anchor_rows[index]].distance_to(point) <= radius * 2.0 and centers[index].distance_to(point) > threshold:
						strays.append(sheep)
		wolf_offsets[index + 1] = wolves.size()
		stray_offsets[index + 1] = strays.size()

	# 3) Resolve exclusive tasks with stable entity-ID tie breaks.
	var wolves_claimed: Dictionary = {}
	var sheep_claimed: Dictionary = {}

	for kind in range(2):
		var claimed: Dictionary = wolves_claimed if kind == 0 else sheep_claimed
		var waiting: Array[int] = []
		for index in range(rows.size()):
			if wolf_rows[index] < 0 and not returning_flags[index]:
				waiting.append(index)
		while not waiting.is_empty():
			var proposals: Dictionary = {}
			for index in waiting:
				var best := -1
				var best_score := INF
				var offsets := wolf_offsets if kind == 0 else stray_offsets
				var members := wolves if kind == 0 else strays
				for member in range(offsets[index], offsets[index + 1]):
					var other := members[member]
					if claimed.has(other):
						continue

					var score: float = context.motion_position[rows[index]].distance_squared_to(_task_point(index, other)) if kind == 0 else -centers[index].distance_squared_to(context.motion_position[other])
					if score < best_score or (is_equal_approx(score, best_score) and best >= 0 and context.identity_entity_id[other] < context.identity_entity_id[best]):
						best = other
						best_score = score
				if best < 0:
					continue

				var distance: float = context.motion_position[rows[index]].distance_squared_to(_task_point(index, best))
				if not proposals.has(best):
					proposals[best] = index
				else:
					var previous: int = proposals[best]
					var previous_distance: float = context.motion_position[rows[previous]].distance_squared_to(_task_point(previous, best))
					if distance < previous_distance or (is_equal_approx(distance, previous_distance) and context.identity_entity_id[rows[index]] < context.identity_entity_id[rows[previous]]):
						proposals[best] = index
			if proposals.is_empty():
				break

			for other in proposals:
				var index: int = proposals[other]
				if kind == 0:
					wolf_rows[index] = other
				else:
					stray_rows[index] = other
				claimed[other] = rows[index]
				waiting.erase(index)

	execute_ms = (Time.get_ticks_usec() - started) / 1000.0

func _task_point(index: int, other: int) -> Vector2:
	return last_positions[index] if other == target_rows[index] and not visible_flags[index] else context.motion_position[other]

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
	var group_wolves := PackedInt32Array()
	var threat_squared: float = pow(radius + size * sqrt(0.5) + context.settings.threat_distance, 2)
	for wolf in context.wolves:
		var threatening: bool = context.wolf_hunting[wolf] != 0
		if not threatening and center.distance_squared_to(context.motion_position[wolf]) <= threat_squared:
			for sheep in flock:
				if context.motion_position[wolf].distance_squared_to(context.motion_position[sheep]) < pow(context.settings.threat_distance, 2):
					threatening = true
					break
		if threatening:
			group_wolves.append(wolf)
	return {"center": sum / count if count > 0 else center, "count": count, "wolves": group_wolves,
		"sheep": GridService.query_snapshot(center, radius * 2.0 + size * sqrt(0.5), AnimalEntity.Kind.SHEEP, grid, stats)}

func resize_output() -> void:
	separations.resize(rows.size())
	refresh_flags.resize(rows.size())
	remaining.resize(rows.size())
	target_rows.resize(rows.size())
	visible_flags.resize(rows.size())
	last_positions.resize(rows.size())
	last_velocities.resize(rows.size())
	anchor_rows.resize(rows.size())
	centers.resize(rows.size())
	reassigned_flags.resize(rows.size())
	returning_flags.resize(rows.size())
	wolf_rows.resize(rows.size())
	stray_rows.resize(rows.size())
	nearby_offsets.resize(rows.size() + 1)
	nearby_offsets.fill(0)
	nearby_members.clear()
	wolf_offsets.resize(rows.size() + 1)
	wolf_offsets.fill(0)
	wolves.clear()
	stray_offsets.resize(rows.size() + 1)
	stray_offsets.fill(0)
	strays.clear()
	wolf_rows.fill(-1)
	stray_rows.fill(-1)
