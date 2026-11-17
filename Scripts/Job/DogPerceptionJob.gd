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

	target.calculate_batch(self)

func apply_result() -> void:
	if snapshot != null:
		target.apply_decision(self)
		return

	target.apply_batch(self)

func _calculate_decision() -> void:
	var started := Time.get_ticks_usec()
	resize_output()
	stats = AnimalSystem.batch_stats(snapshot.stats, snapshot.detailed)
	var settings: SheepdogConfig = snapshot.config.sheepdog
	var radius: float = settings.local_flock_radius
	var assignments := snapshot.dog_region.duplicate()
	region_coverage.resize(grid.region_counts.size())
	region_coverage.fill(0)
	region_threats.resize(grid.region_counts.size())
	region_threats.fill(0)
	for dog in rows:
		if grid.has_region(assignments[dog]):
			region_coverage[assignments[dog]] += 1

	# 1) Assign occupied regions in stable entity-ID order.
	var ordered: Array[int] = []
	for dog in rows:
		ordered.append(dog)
	ordered.sort_custom(func(first: int, second: int) -> bool: return snapshot.identity_entity_id[first] < snapshot.identity_entity_id[second])
	for dog in ordered:
		var current: int = assignments[dog]
		var valid := grid.has_region(current)
		if valid and snapshot.dog_assignment_remaining[dog] > 0.0:
			continue

		if valid:
			region_coverage[current] -= 1
		var best := current if valid else -1
		var current_score := _region_score(dog, current) if valid else INF
		var best_score := current_score
		for region in grid.occupied_regions:
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
		refresh_flags[index] = int(not snapshot.memory_perception_ready[dog] or snapshot.memory_perception_remaining[dog] <= 0.0)
		separations[index] = AnimalSystem.snapshot_separation(dog, snapshot, grid, stats, bool(refresh_flags[index]))
		target_rows[index] = snapshot.memory_target[dog]
		var target_row := target_rows[index]
		var visible := target_row >= 0 and AnimalSystem.snapshot_can_see(dog, snapshot.motion_position[target_row], snapshot)
		visible_flags[index] = int(visible)
		last_positions[index] = snapshot.motion_position[target_row] if visible else snapshot.memory_last_seen_position[dog]
		last_velocities[index] = snapshot.motion_velocity[target_row] if visible else snapshot.memory_last_seen_velocity[dog]
		region_ids[index] = assignments[dog]
		reassigned_flags[index] = int(not grid.has_region(snapshot.dog_region[dog]) or snapshot.dog_assignment_remaining[dog] <= 0.0)
		centers[index] = snapshot.dog_protection_center[dog]
		returning_flags[index] = snapshot.dog_returning[dog]
		if region_ids[index] >= 0:
			var region := region_ids[index]
			if not groups.has(region):
				groups[region] = _local_group(region, stats)
			var group: Group = groups[region]
			region_threats[region] = group.wolves.size()
			centers[index] = group.center
			if snapshot.motion_position[dog].distance_to(centers[index]) > settings.leash_distance:
				returning_flags[index] = 1
			if not returning_flags[index]:
				for wolf in group.wolves:
					if AnimalSystem.snapshot_can_see(dog, snapshot.motion_position[wolf], snapshot):
						wolves.append(wolf)
				var remembered: int = snapshot.memory_target[dog]
				if remembered >= 0 and not visible_flags[index] and snapshot.memory_unseen_elapsed[dog] < settings.memory_duration and not wolves.slice(wolf_offsets[index], wolves.size()).has(remembered):
					wolves.append(remembered)
				for sheep in group.sheep:
					var point: Vector2 = snapshot.motion_position[sheep]
					var threshold: float = radius * settings.collect_complete_ratio if sheep == snapshot.dog_collected_sheep[dog] else radius
					if grid.region_centers[region].distance_to(point) <= radius * 2.0 and centers[index].distance_to(point) > threshold:
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

					var score: float = snapshot.motion_position[rows[index]].distance_squared_to(_task_point(index, other)) if kind == 0 else -centers[index].distance_squared_to(snapshot.motion_position[other])
					if score < best_score or (is_equal_approx(score, best_score) and best >= 0 and snapshot.identity_entity_id[other] < snapshot.identity_entity_id[best]):
						best = other
						best_score = score
				if best < 0:
					continue

				var distance: float = snapshot.motion_position[rows[index]].distance_squared_to(_task_point(index, best))
				if not proposals.has(best):
					proposals[best] = index
				else:
					var previous: int = proposals[best]
					var previous_distance: float = snapshot.motion_position[rows[previous]].distance_squared_to(_task_point(previous, best))
					if distance < previous_distance or (is_equal_approx(distance, previous_distance) and snapshot.identity_entity_id[rows[index]] < snapshot.identity_entity_id[rows[previous]]):
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
	return last_positions[index] if other == target_rows[index] and not visible_flags[index] else snapshot.motion_position[other]

func _region_score(dog: int, region: int) -> float:
	return snapshot.motion_position[dog].distance_to(grid.region_centers[region]) / snapshot.config.sheepdog.local_flock_radius + region_coverage[region] * snapshot.config.sheepdog.coverage_weight

func _local_group(region: int, stats: Dictionary) -> Group:
	var radius: float = snapshot.config.sheepdog.local_flock_radius
	var center := grid.region_centers[region]
	var flock := GridService.query_snapshot(center, radius, AnimalEntity.Kind.SHEEP, grid, stats)
	var sum := Vector2.ZERO
	var count := 0
	for sheep in flock:
		if center.distance_squared_to(snapshot.motion_position[sheep]) <= radius * radius:
			sum += snapshot.motion_position[sheep]
			count += 1
	var group_wolves := PackedInt32Array()
	var threat_distance: float = snapshot.config.sheepdog.threat_distance
	var wolves_nearby := GridService.query_snapshot(center, radius + threat_distance, AnimalEntity.Kind.WOLF, grid, stats)
	for wolf in wolves_nearby:
		var threatening := false
		for sheep in flock:
			if center.distance_squared_to(snapshot.motion_position[sheep]) <= radius * radius and snapshot.motion_position[wolf].distance_squared_to(snapshot.motion_position[sheep]) <= threat_distance * threat_distance:
				threatening = true
				break
		if threatening:
			group_wolves.append(wolf)
	var result := Group.new()
	result.center = sum / count if count > 0 else center
	result.count = count
	result.wolves = group_wolves
	result.sheep = GridService.query_snapshot(center, radius * 2.0, AnimalEntity.Kind.SHEEP, grid, stats)
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
