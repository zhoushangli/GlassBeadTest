class_name DogPerceptionJob
extends Job

class Group extends RefCounted:
	var center := Vector2.ZERO
	var count: int = 0
	var wolves := PackedInt32Array()
	var sheep := PackedInt32Array()

var groups: Array[Group] = []

var separations := PackedVector2Array()
var refresh_flags := PackedByteArray()
var remaining := PackedFloat64Array()
var target_rows := PackedInt32Array()
var visible_flags := PackedByteArray()
var last_positions := PackedVector2Array()
var last_velocities := PackedVector2Array()

var region_ids := PackedInt32Array()
var region_coverage := PackedInt32Array()
var region_threats := PackedInt32Array()
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
	if snapshot != null:
		_calculate_decision()
		return

	_calculate_batch()

func apply_result() -> void:
	if snapshot != null:
		var started_at := Time.get_ticks_usec()
		_apply_decision()
		record_application(2, started_at)
		return

	_apply_batch()

func _calculate_decision() -> void:
	var started := Time.get_ticks_usec()
	resize_output()
	stats = Job.batch_stats(snapshot.stats, snapshot.detailed)
	var settings: SheepdogConfig = snapshot.config.sheepdog
	var radius: float = settings.local_flock_radius
	var assignments := snapshot.dog.region.duplicate()
	region_coverage.resize(grid.regions.counts.size())
	region_coverage.fill(0)
	region_threats.resize(grid.regions.counts.size())
	region_threats.fill(0)
	for dog in rows:
		if grid.has_region(assignments[dog]):
			region_coverage[assignments[dog]] += 1

	# 1) Assign occupied regions in stable entity-ID order.
	var ordered: Array[int] = []
	for dog in rows:
		ordered.append(dog)
	ordered.sort_custom(func(first: int, second: int) -> bool: return snapshot.identity.entity_id[first] < snapshot.identity.entity_id[second])
	for dog in ordered:
		var current: int = assignments[dog]
		var valid := grid.has_region(current)
		if valid and snapshot.dog.assignment_remaining[dog] > 0.0:
			continue

		if valid:
			region_coverage[current] -= 1
		var best := current if valid else -1
		var current_score := _region_score(dog, current) if valid else INF
		var best_score := current_score
		for region in grid.regions.occupied:
			var score := _region_score(dog, region)
			if score < best_score or (is_equal_approx(score, best_score) and (best < 0 or region < best)):
				best = region
				best_score = score
		assignments[dog] = best if not valid or best_score <= current_score * (1.0 - settings.reassignment_improvement) else current
		if assignments[dog] >= 0:
			region_coverage[assignments[dog]] += 1

	# 2) Collect perception and shared local-group candidates.
	var groups: Dictionary = {}
	for index in range(rows.size()):
		var dog := rows[index]
		refresh_flags[index] = int(not snapshot.memory.perception_ready[dog] or snapshot.memory.perception_remaining[dog] <= 0.0)
		separations[index] = Job.snapshot_separation(dog, snapshot, grid, stats, bool(refresh_flags[index]))
		target_rows[index] = snapshot.memory.target[dog]
		var target_row := target_rows[index]
		var visible := target_row >= 0 and Job.snapshot_can_see(dog, snapshot.motion.position[target_row], snapshot)
		visible_flags[index] = int(visible)
		last_positions[index] = snapshot.motion.position[target_row] if visible else snapshot.memory.last_seen_position[dog]
		last_velocities[index] = snapshot.motion.velocity[target_row] if visible else snapshot.memory.last_seen_velocity[dog]
		region_ids[index] = assignments[dog]
		reassigned_flags[index] = int(not grid.has_region(snapshot.dog.region[dog]) or snapshot.dog.assignment_remaining[dog] <= 0.0)
		centers[index] = snapshot.dog.protection_center[dog]
		returning_flags[index] = snapshot.dog.returning[dog]
		if region_ids[index] >= 0:
			var region := region_ids[index]
			if not groups.has(region):
				groups[region] = _local_group(region, stats)
			var group: Group = groups[region]
			region_threats[region] = group.wolves.size()
			centers[index] = group.center
			if snapshot.motion.position[dog].distance_to(centers[index]) > settings.leash_distance:
				returning_flags[index] = 1
			if not returning_flags[index]:
				for wolf in group.wolves:
					if Job.snapshot_can_see(dog, snapshot.motion.position[wolf], snapshot):
						wolves.append(wolf)
				var remembered: int = snapshot.memory.target[dog]
				if remembered >= 0 and not visible_flags[index] and snapshot.memory.unseen_elapsed[dog] < settings.memory_duration and not wolves.slice(wolf_offsets[index], wolves.size()).has(remembered):
					wolves.append(remembered)
				for sheep in group.sheep:
					var point: Vector2 = snapshot.motion.position[sheep]
					var threshold: float = radius * settings.collect_complete_ratio if sheep == snapshot.dog.collected_sheep[dog] else radius
					if grid.regions.centers[region].distance_to(point) <= radius * 2.0 and centers[index].distance_to(point) > threshold:
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

					var score: float = snapshot.motion.position[rows[index]].distance_squared_to(_task_point(index, other)) if kind == 0 else -centers[index].distance_squared_to(snapshot.motion.position[other])
					if score < best_score or (is_equal_approx(score, best_score) and best >= 0 and snapshot.identity.entity_id[other] < snapshot.identity.entity_id[best]):
						best = other
						best_score = score
				if best < 0:
					continue

				var distance: float = snapshot.motion.position[rows[index]].distance_squared_to(_task_point(index, best))
				if not proposals.has(best):
					proposals[best] = index
				else:
					var previous: int = proposals[best]
					var previous_distance: float = snapshot.motion.position[rows[previous]].distance_squared_to(_task_point(previous, best))
					if distance < previous_distance or (is_equal_approx(distance, previous_distance) and snapshot.identity.entity_id[rows[index]] < snapshot.identity.entity_id[rows[previous]]):
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
	return last_positions[index] if other == target_rows[index] and not visible_flags[index] else snapshot.motion.position[other]

func _region_score(dog: int, region: int) -> float:
	return snapshot.motion.position[dog].distance_to(grid.regions.centers[region]) / snapshot.config.sheepdog.local_flock_radius + region_coverage[region] * snapshot.config.sheepdog.coverage_weight

func _local_group(region: int, stats: Dictionary) -> Group:
	var radius: float = snapshot.config.sheepdog.local_flock_radius
	var center := grid.regions.centers[region]
	var flock := GridSnapshot.query_snapshot(center, radius, AnimalEntity.Kind.SHEEP, grid, stats)
	var sum := Vector2.ZERO
	var count := 0
	for sheep in flock:
		if center.distance_squared_to(snapshot.motion.position[sheep]) <= radius * radius:
			sum += snapshot.motion.position[sheep]
			count += 1

	var group_wolves := PackedInt32Array()
	var threat_distance: float = snapshot.config.sheepdog.threat_distance
	var wolves_nearby := GridSnapshot.query_snapshot(center, radius + threat_distance, AnimalEntity.Kind.WOLF, grid, stats)
	for wolf in wolves_nearby:
		var threatening := false
		for sheep in flock:
			if center.distance_squared_to(snapshot.motion.position[sheep]) <= radius * radius and snapshot.motion.position[wolf].distance_squared_to(snapshot.motion.position[sheep]) <= threat_distance * threat_distance:
				threatening = true
				break

		if threatening:
			group_wolves.append(wolf)

	var result: Group = Group.new()
	result.center = sum / count if count > 0 else center
	result.count = count
	result.wolves = group_wolves
	result.sheep = GridSnapshot.query_snapshot(center, radius * 2.0, AnimalEntity.Kind.SHEEP, grid, stats)
	return result

func resize_output() -> void:
	separations.resize(rows.size())
	refresh_flags.resize(rows.size())
	remaining.resize(rows.size())
	target_rows.resize(rows.size())
	visible_flags.resize(rows.size())
	last_positions.resize(rows.size())
	last_velocities.resize(rows.size())
	region_ids.resize(rows.size())
	region_ids.fill(-1)
	anchor_rows.resize(rows.size())
	anchor_rows.fill(-1)
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

func copy_input(source: Job) -> void:
	super.copy_input(source)
	groups = (source as DogPerceptionJob).groups

func release_input() -> void:
	super.release_input()
	groups = []
	region_coverage = PackedInt32Array()
	region_threats = PackedInt32Array()

func _calculate_batch() -> void:
	var data := batch_input
	resize_output()
	var stats := Job.batch_stats(spatial_stats, detailed)
	for index in range(rows.size()):
		var row := rows[index]
		calculate_perception(row, self, stats, index, remaining, refresh_flags, separations, nearby_offsets, nearby_members)
		if row < groups.size() and groups[row] != null:
			var group: DogPerceptionJob.Group = groups[row]
			for wolf_row in group.wolves:
				if can_see(data.index.handles[row], data.motion.position[wolf_row]):
					wolves.append(wolf_row)

			var remembered := data.live(data.memory.target[row])
			if remembered != null and not data.memory.target_visible[row] and data.memory.unseen_elapsed[row] < config.sheepdog.memory_duration:
				wolves.append(remembered.row)

			var anchor := data.live(data.dog.protected_sheep[row])
			var collected := data.live(data.dog.collected_sheep[row])
			for sheep_row in group.sheep:
				var point := data.motion.position[sheep_row]
				var distance := data.dog.protection_center[row].distance_to(point)
				var threshold: float = config.sheepdog.local_flock_radius * config.sheepdog.collect_complete_ratio if collected != null and sheep_row == collected.row else config.sheepdog.local_flock_radius
				if data.motion.position[anchor.row].distance_to(point) <= config.sheepdog.local_flock_radius * 2.0 and distance > threshold:
					strays.append(sheep_row)

		wolf_offsets[index + 1] = wolves.size()
		stray_offsets[index + 1] = strays.size()

	self.stats = stats

func _apply_batch() -> void:
	submit_stats(stats)
	for index in range(rows.size()):
		var row := rows[index]
		submit_perception(row, remaining[index], bool(refresh_flags[index]), nearby_members.slice(nearby_offsets[index], nearby_offsets[index + 1]), separations[index], delta, false)
		data.dog.wolf_candidates[row].clear()
		data.dog.stray_candidates[row].clear()
		for member in range(wolf_offsets[index], wolf_offsets[index + 1]):
			data.dog.wolf_candidates[row].append(data.index.handles[wolves[member]])
		for member in range(stray_offsets[index], stray_offsets[index + 1]):
			data.dog.stray_candidates[row].append(data.index.handles[strays[member]])

func _apply_decision() -> void:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	submit_stats(stats)
	var coverage := PackedInt32Array()
	coverage.resize(grid.regions.counts.size())

	# 1) Revalidate current assignments so delayed work cannot overwrite a newer decision.
	for index in range(rows.size()):
		var snapshot_row := rows[index]
		var animal := snapshot_animal(snapshot, snapshot_row)
		if animal == null:
			continue

		var row := animal.row
		if data.dog.region[row] != snapshot.dog.region[snapshot_row] or data.dog.returning[row] != snapshot.dog.returning[snapshot_row] or data.live(data.memory.target[row]) != snapshot_animal(snapshot, target_rows[index]) or data.live(data.dog.collected_sheep[row]) != snapshot_animal(snapshot, snapshot.dog.collected_sheep[snapshot_row]):
			continue

		var wolf := snapshot_animal(snapshot, wolf_rows[index])
		var stray := snapshot_animal(snapshot, stray_rows[index])
		if (wolf_rows[index] >= 0 and wolf == null) or (stray_rows[index] >= 0 and stray == null) or (target_rows[index] >= 0 and snapshot_animal(snapshot, target_rows[index]) == null):
			continue

		apply_snapshot_perception(row, snapshot_row, snapshot, separations[index], bool(refresh_flags[index]), target_rows[index], bool(visible_flags[index]), last_positions[index], last_velocities[index])
		data.dog.region[row] = region_ids[index]
		data.dog.protected_sheep[row] = null
		if reassigned_flags[index]:
			data.dog.assignment_remaining[row] = maxf(0.0, g_gameplayEngine.config.sheepdog.reassignment_interval - (g_gameplayEngine.simulation_time - snapshot.time))
		if data.dog.region[row] >= 0:
			data.dog.protection_center[row] = centers[index]
		data.dog.returning[row] = int(returning_flags[index]) if data.dog.region[row] >= 0 else 0
		g_gameplayEngine.dog_system.apply_assignment(animal, wolf, stray)
		g_gameplayEngine.advance_decision(animal)

	for row in g_gameplayEngine.data_service.animals.index.dog_rows:
		var region := data.dog.region[row]
		if region >= 0 and region < coverage.size():
			coverage[region] += 1

	var service: GridService = g_gameplayEngine.grid_service
	spatial.debug.dog_snapshot = grid
	spatial.debug.dog_region_coverage = coverage
	spatial.debug.dog_region_threats = region_threats
