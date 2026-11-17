class_name AnimalSystem
extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func decision_snapshot(due: PackedInt32Array = PackedInt32Array([0, 1, 2]), gpu: bool = false) -> AnimalSnapshot:
	# 1) Capture common inputs and species membership before submitting worker jobs.
	var engine := g_gameplayEngine
	var snapshot := AnimalSnapshot.new()
	snapshot.captured_usec = Time.get_ticks_usec()
	snapshot.time = engine.simulation_time
	snapshot.stats = engine.grid_service.spatial_stats_enabled
	snapshot.detailed = engine.profile_service.detailed_stats_enabled
	snapshot.config = engine.animal_service.snapshot_config
	snapshot.distance = snapshot.config.separation_distance
	snapshot.interval = snapshot.config.perception_interval
	snapshot.due = due
	snapshot.gpu = gpu
	snapshot.sheep = engine.entity_service.sheep_rows.duplicate()
	snapshot.wolves = engine.entity_service.wolf_rows.duplicate()
	snapshot.dogs = engine.entity_service.dog_rows.duplicate()

	snapshot.identity_animal_id = data.identity_animal_id.slice(0, data.active_count)
	snapshot.identity_entity_id = data.identity_entity_id.slice(0, data.active_count)
	snapshot.identity_kind = PackedInt32Array(Array(data.identity_kind.slice(0, data.active_count)))
	snapshot.motion_position = data.motion_position.slice(0, data.active_count)
	snapshot.motion_velocity = data.motion_velocity.slice(0, data.active_count)
	snapshot.motion_separation = data.motion_separation.slice(0, data.active_count)
	snapshot.memory_perception_ready = data.memory_perception_ready.slice(0, data.active_count)
	snapshot.memory_perception_remaining = data.memory_perception_remaining.slice(0, data.active_count)
	snapshot.wolf_hunting = data.wolf_hunting.slice(0, data.active_count)

	# 2) Copy optional columns only for the species or GPU passes that need them.
	if due.has(0) or gpu:
		snapshot.sheep_panic_strength = data.sheep_panic_strength.slice(0, data.active_count)
		snapshot.sheep_panic_source = data.sheep_panic_source.slice(0, data.active_count)
		snapshot.sheep_panic_revision = data.sheep_panic_revision.slice(0, data.active_count)
		snapshot.motion_wander_point = data.motion_wander_point.slice(0, data.active_count)

	if due.has(1) or due.has(2):
		snapshot.motion_facing = data.motion_facing.slice(0, data.active_count)
		snapshot.memory_vision_radius_squared = data.memory_vision_radius_squared.slice(0, data.active_count)
		snapshot.memory_vision_cos = data.memory_vision_cos.slice(0, data.active_count)
		snapshot.memory_target_visible = data.memory_target_visible.slice(0, data.active_count)
		snapshot.memory_unseen_elapsed = data.memory_unseen_elapsed.slice(0, data.active_count)
		snapshot.memory_last_seen_position = data.memory_last_seen_position.slice(0, data.active_count)
		snapshot.memory_last_seen_velocity = data.memory_last_seen_velocity.slice(0, data.active_count)

	if due.has(1):
		snapshot.wolf_resting = data.wolf_resting.slice(0, data.active_count)
		snapshot.wolf_retreating = data.wolf_retreating.slice(0, data.active_count)

	if due.has(2):
		snapshot.dog_region = data.dog_region.slice(0, data.active_count)
		snapshot.dog_returning = data.dog_returning.slice(0, data.active_count)
		snapshot.dog_assignment_remaining = data.dog_assignment_remaining.slice(0, data.active_count)
		snapshot.dog_protection_center = data.dog_protection_center.slice(0, data.active_count)

	if due.has(1) or due.has(2):
		# 1) Convert live handles to snapshot-local rows before leaving the main thread.
		snapshot.memory_target.resize(data.active_count)
		snapshot.memory_target.fill(-1)
		var observers := PackedInt32Array()
		if due.has(1):
			observers.append_array(snapshot.wolves)
		if due.has(2):
			observers.append_array(snapshot.dogs)
		for row in observers:
			var handle := data.live(data.memory_target[row])
			snapshot.memory_target[row] = handle.row if handle != null else -1

	if due.has(2):
		snapshot.dog_collected_sheep.resize(data.active_count)
		snapshot.dog_collected_sheep.fill(-1)
		for row in snapshot.dogs:
			var collected := data.live(data.dog_collected_sheep[row])
			snapshot.dog_collected_sheep[row] = collected.row if collected != null else -1

	snapshot.prepare_ms = (Time.get_ticks_usec() - snapshot.captured_usec) / 1000.0
	return snapshot

static func snapshot_can_see(row: int, point: Vector2, snapshot: AnimalSnapshot) -> bool:
	var offset: Vector2 = point - snapshot.motion_position[row]
	return offset.length_squared() <= snapshot.memory_vision_radius_squared[row] and (offset.is_zero_approx() or snapshot.motion_facing[row].dot(offset.normalized()) + 0.000001 >= snapshot.memory_vision_cos[row])

static func snapshot_separation(row: int, snapshot: AnimalSnapshot, grid: GridSnapshot, stats: Dictionary, refresh: bool) -> Vector2:
	var separation: Vector2 = snapshot.motion_separation[row]
	if refresh:
		separation = Vector2.ZERO
		var distance: float = snapshot.distance
		var nearby := GridService.query_snapshot(snapshot.motion_position[row], distance, grid.kinds[row], grid, stats)
		for other in nearby:
			if other == row:
				continue

			var offset: Vector2 = snapshot.motion_position[row] - snapshot.motion_position[other]
			var length := offset.length()
			if distance <= 0.0 or length >= distance:
				continue

			var direction := offset.normalized() if length >= 0.001 else (Vector2.RIGHT if snapshot.identity_entity_id[row] < snapshot.identity_entity_id[other] else Vector2.LEFT)
			separation += direction * (1.0 - length / distance)
	return separation

# Resolve snapshot identity against current storage instead of trusting an old row.
# e.g. a captured animal resolves to null even if its former row now holds a survivor.
func snapshot_animal(snapshot: AnimalSnapshot, index: int) -> AnimalEntity:
	if index < 0 or index >= snapshot.identity_animal_id.size():
		return null

	var row := data.row_of_id(snapshot.identity_animal_id[index])
	return data.handles[row] if row >= 0 and row < data.active_count and data.identity_alive[row] else null

func apply_snapshot_perception(row: int, snapshot_row: int, snapshot: AnimalSnapshot, separation: Vector2, refresh: bool, target: int, visible: bool, last_position: Vector2, last_velocity: Vector2) -> void:
	# 1) Subtract snapshot age so completed work does not restart an old sampling interval.
	if refresh:
		data.motion_separation[row] = separation
		data.memory_perception_ready[row] = 1
		var interval: float = snapshot.interval
		if not snapshot.memory_perception_ready[snapshot_row]:
			interval *= fmod(snapshot.identity_entity_id[snapshot_row] * 0.618034, 1.0)
		data.memory_perception_remaining[row] = maxf(0.0, interval - (g_gameplayEngine.simulation_time - snapshot.time))

	if data.live(data.memory_target[row]) != snapshot_animal(snapshot, target):
		return

	data.memory_target_visible[row] = int(visible)
	if visible:
		data.memory_last_seen_position[row] = last_position
		data.memory_last_seen_velocity[row] = last_velocity
		data.memory_unseen_elapsed[row] = g_gameplayEngine.simulation_time - snapshot.time

func prepare_job(job: Job, delta: float) -> void:
	job.delta = delta
	job.grid = g_gameplayEngine.grid_service.query_context()
	job.config = g_gameplayEngine.config
	job.common = self
	job.distance = job.config.separation_distance
	job.interval = job.config.perception_interval
	job.spatial_stats = g_gameplayEngine.grid_service.spatial_stats_enabled
	job.detailed = g_gameplayEngine.profile_service.detailed_stats_enabled

static func batch_stats(enabled: bool, detailed: bool) -> Dictionary:
	return {"enabled": enabled, "detailed": detailed, "queries": 0, "candidates": 0, "max_candidates": 0,
		"hotspots": {"NearbyQuery": 0.0, "Separation": 0.0, "NeighborScan": 0.0, "WolfTarget": 0.0, "DogAnchor": 0.0},
		"calls": {"NearbyQuery": 0, "Separation": 0, "NeighborScan": 0, "WolfTarget": 0, "DogAnchor": 0}}

func calculate_perception(row: int, job: Job, stats: Dictionary, index: int, remaining_values: PackedFloat64Array, refresh_flags: PackedByteArray, separations: PackedVector2Array, nearby_offsets: PackedInt32Array, nearby_members: PackedInt32Array) -> void:
	var remaining: float = data.memory_perception_remaining[row] - job.delta
	var refresh := not data.memory_perception_ready[row] or remaining <= 0.0
	var nearby := data.memory_nearby[row]
	var separation := data.motion_separation[row]
	if refresh:
		nearby = GridService.query_snapshot(data.motion_position[row], job.distance, data.identity_kind[row], job.grid, stats)
		var started_at := Time.get_ticks_usec() if stats.detailed else 0
		separation = Vector2.ZERO
		var distance_limit: float = job.distance
		var positions: PackedVector2Array = job.grid.positions
		var kinds: PackedInt32Array = job.grid.kinds
		if distance_limit > 0.0:
			for other in nearby:
				if other == row or kinds[other] != data.identity_kind[row]:
					continue

				var offset := data.motion_position[row] - positions[other]
				var squared := offset.length_squared()
				if squared >= distance_limit * distance_limit:
					continue

				var distance := sqrt(squared)
				var direction := offset.normalized()
				if distance < 0.001:
					direction = Vector2.RIGHT if data.identity_entity_id[row] < data.identity_entity_id[other] else Vector2.LEFT
				separation += direction * (1.0 - distance / distance_limit)
		if stats.detailed:
			stats.hotspots.Separation += (Time.get_ticks_usec() - started_at) / 1000.0
			stats.calls.Separation += 1
		remaining = job.interval
		if not data.memory_perception_ready[row]:
			remaining *= fmod(data.identity_entity_id[row] * 0.618034, 1.0)

	remaining_values[index] = remaining
	refresh_flags[index] = int(refresh)
	separations[index] = separation
	nearby_members.append_array(nearby)
	nearby_offsets[index + 1] = nearby_members.size()

func submit_perception(row: int, remaining: float, refresh: bool, nearby: PackedInt32Array, separation: Vector2, delta: float, advance_wander: bool = true) -> void:
	if advance_wander:
		data.motion_wander_remaining[row] -= delta
	data.memory_perception_remaining[row] = remaining
	data.memory_perception_ready[row] = 1
	if refresh:
		data.memory_nearby[row] = nearby
		data.motion_separation[row] = separation

func submit_stats(stats: Dictionary) -> void:
	var grid: GridService = g_gameplayEngine.grid_service
	grid.spatial_query_count += stats.queries
	grid.spatial_candidate_count += stats.candidates
	grid.spatial_max_candidates = maxi(grid.spatial_max_candidates, stats.max_candidates)
	if stats.detailed:
		var profile: ProfileService = g_gameplayEngine.profile_service
		for name in stats.hotspots:
			profile.last_hotspots_ms[name] += stats.hotspots[name]
			profile.last_hotspot_calls[name] += stats.calls[name]

func update_movement(delta: float) -> void:
	g_gameplayEngine.entity_service.update_movement(delta)

func is_live(animal: AnimalEntity, other: AnimalEntity) -> bool:
	return data.live(other) != null

func can_see(animal: AnimalEntity, point: Vector2) -> bool:
	var row := animal.row
	var offset := point - data.motion_position[row]
	if offset.length_squared() > data.memory_vision_radius_squared[row]:
		return false

	return offset.is_zero_approx() or data.motion_facing[row].dot(offset.normalized()) + 0.000001 >= data.memory_vision_cos[row]

func observe_target(animal: AnimalEntity, delta: float) -> void:
	var memory_target_visible := data.memory_target_visible
	var memory_unseen_elapsed := data.memory_unseen_elapsed
	var row := animal.row
	var target := data.live(data.memory_target[row])
	if target == null:
		memory_target_visible[row] = 0
		memory_unseen_elapsed[row] = 0.0
		return

	memory_target_visible[row] = int(can_see(animal, data.motion_position[target.row]))
	if memory_target_visible[row]:
		data.memory_last_seen_position[row] = data.motion_position[target.row]
		data.memory_last_seen_velocity[row] = data.motion_velocity[target.row]
		memory_unseen_elapsed[row] = 0.0
	else:
		memory_unseen_elapsed[row] += delta

func calculate_observation(row: int, delta: float, job: WolfPerceptionJob, index: int) -> void:
	var target := data.live(data.memory_target[row])
	job.visible_flags[index] = 0
	job.unseen_elapsed[index] = 0.0
	job.last_positions[index] = Vector2.ZERO
	job.last_velocities[index] = Vector2.ZERO
	if target == null:
		return

	var visible := can_see(data.handles[row], data.motion_position[target.row])
	job.visible_flags[index] = int(visible)
	job.unseen_elapsed[index] = 0.0 if visible else data.memory_unseen_elapsed[row] + delta
	job.last_positions[index] = data.motion_position[target.row]
	job.last_velocities[index] = data.motion_velocity[target.row]

func submit_observation(row: int, visible: bool, elapsed: float, position: Vector2, velocity: Vector2) -> void:
	data.memory_target_visible[row] = int(visible)
	data.memory_unseen_elapsed[row] = elapsed
	if visible:
		data.memory_last_seen_position[row] = position
		data.memory_last_seen_velocity[row] = velocity

func perceive(animal: AnimalEntity, delta: float) -> void:
	var memory_perception_ready := data.memory_perception_ready
	var memory_perception_remaining := data.memory_perception_remaining
	var row := animal.row
	data.motion_wander_remaining[row] -= delta
	memory_perception_remaining[row] -= delta
	if not memory_perception_ready[row] or memory_perception_remaining[row] <= 0.0:
		var service: GridService = g_gameplayEngine.grid_service
		data.memory_nearby[row] = service.get_nearby_indices(data.motion_position[row], g_gameplayEngine.config.separation_distance, data.identity_kind[row])
		var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
		_scan_separation(animal, service)
		if g_gameplayEngine.profile_service.detailed_stats_enabled:
			g_gameplayEngine.profile_service.record_hotspot("Separation", started)
		memory_perception_remaining[row] = g_gameplayEngine.config.perception_interval
		if not memory_perception_ready[row]:
			memory_perception_remaining[row] *= fmod(data.identity_entity_id[row] * 0.618034, 1.0)
		memory_perception_ready[row] = 1

	if data.identity_kind[row] == AnimalEntity.Kind.SHEEP:
		var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
		g_gameplayEngine.sheep_system._scan_neighbors(animal, g_gameplayEngine.grid_service)
		if g_gameplayEngine.profile_service.detailed_stats_enabled:
			g_gameplayEngine.profile_service.record_hotspot("NeighborScan", started)

func _scan_separation(animal: AnimalEntity, service: GridService) -> void:
	var row := animal.row
	data.motion_separation[row] = Vector2.ZERO
	var distance_limit: float = g_gameplayEngine.config.separation_distance
	if distance_limit <= 0.0:
		return

	var position := data.motion_position[row]
	var kind := data.identity_kind[row]
	var entity_id := data.identity_entity_id[row]
	var positions := service.perception_positions
	var kinds := service.perception_kinds
	var separation := Vector2.ZERO
	for index in data.memory_nearby[row]:
		if index == row or kinds[index] != kind:
			continue

		var offset := position - positions[index]
		var distance_squared := offset.length_squared()
		if distance_squared >= distance_limit * distance_limit:
			continue

		var distance := sqrt(distance_squared)
		var direction := offset.normalized()
		if distance < 0.001:
			direction = Vector2.RIGHT if entity_id < data.identity_entity_id[index] else Vector2.LEFT
		separation += direction * (1.0 - distance / distance_limit)

	data.motion_separation[row] = separation

func decide(animal: AnimalEntity, delta: float) -> void:
	if data.identity_kind[animal.row] == AnimalEntity.Kind.SHEEP:
		return

	var row := animal.row
	var settings: Resource = data.settings[row]
	data.motion_intent[row] = AnimalData.MotionIntent.STOP
	data.motion_desired_velocity[row] = Vector2.ZERO
	data.motion_speed_limit[row] = settings.move_speed
	var profile: ProfileService = g_gameplayEngine.profile_service
	var started_at := Time.get_ticks_usec() if profile.performance_stats_enabled else 0
	data.brain_instance[row].update(delta)
	if profile.performance_stats_enabled:
		profile.record_duration("Brain/Update", (Time.get_ticks_usec() - started_at) / 1000.0)

func get_wander_point(animal: AnimalEntity, distance: float) -> Vector2:
	var motion_wander_point := data.motion_wander_point
	var row := animal.row
	if data.motion_wander_remaining[row] <= 0.0 or data.motion_position[row].distance_to(motion_wander_point[row]) < 15.0:
		var direction := Vector2.from_angle(g_gameplayEngine.rng.randf_range(-PI, PI))
		motion_wander_point[row] = clamp_to_arena(animal, data.motion_position[row] + direction * distance)
		data.motion_wander_remaining[row] = g_gameplayEngine.rng.randf_range(1.5, 3.5)
	return motion_wander_point[row]

func clamp_to_arena(animal: AnimalEntity, point: Vector2) -> Vector2:
	return point.clamp(Vector2(12.0, 94.0), g_gameplayEngine.config.arena_size - Vector2(12.0, 58.0))

func move_towards(animal: AnimalEntity, point: Vector2, speed: float, _delta: float) -> void:
	var row := animal.row
	data.motion_intent[row] = AnimalData.MotionIntent.POINT
	data.motion_movement_goal[row] = point
	data.motion_speed_limit[row] = speed

func update_steering(delta: float) -> void:
	g_gameplayEngine.sheep_system.update_steering(delta)
	g_gameplayEngine.wolf_system.prepare_motion_goals()
	g_gameplayEngine.dog_system.prepare_motion_goals()

	for row in range(data.active_count):
		if data.motion_intent[row] != AnimalData.MotionIntent.POINT:
			continue

		var difference := data.motion_movement_goal[row] - data.motion_position[row]
		data.motion_desired_velocity[row] = difference.normalized() * minf(data.motion_speed_limit[row], difference.length() / maxf(delta, 0.00001))

func submit_velocity(animal: AnimalEntity, desired: Vector2, speed: float) -> void:
	var row := animal.row
	data.motion_desired_velocity[row] = desired
	data.motion_speed_limit[row] = speed
	data.motion_movement_goal[row] = data.motion_position[row] + data.motion_desired_velocity[row]
