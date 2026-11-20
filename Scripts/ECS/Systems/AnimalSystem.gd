class_name AnimalSystem
extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func submit_perception(row: int, remaining: float, refresh: bool, nearby: PackedInt32Array, separation: Vector2, delta: float, advance_wander: bool = true) -> void:
	if advance_wander:
		data.motion.wander_remaining[row] -= delta
	data.memory.perception_remaining[row] = remaining
	data.memory.perception_ready[row] = 1
	if refresh:
		data.memory.nearby[row] = nearby
		data.motion.separation[row] = separation

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
	var offset := point - data.motion.position[row]
	if offset.length_squared() > data.memory.vision_radius_squared[row]:
		return false

	return offset.is_zero_approx() or data.motion.facing[row].dot(offset.normalized()) + 0.000001 >= data.memory.vision_cos[row]

func observe_target(animal: AnimalEntity, delta: float) -> void:
	var memory_target_visible := data.memory.target_visible
	var memory_unseen_elapsed := data.memory.unseen_elapsed
	var row := animal.row
	var target := data.live(data.memory.target[row])
	if target == null:
		memory_target_visible[row] = 0
		memory_unseen_elapsed[row] = 0.0
		return

	memory_target_visible[row] = int(can_see(animal, data.motion.position[target.row]))
	if memory_target_visible[row]:
		data.memory.last_seen_position[row] = data.motion.position[target.row]
		data.memory.last_seen_velocity[row] = data.motion.velocity[target.row]
		memory_unseen_elapsed[row] = 0.0
	else:
		memory_unseen_elapsed[row] += delta

func submit_observation(row: int, visible: bool, elapsed: float, position: Vector2, velocity: Vector2) -> void:
	data.memory.target_visible[row] = int(visible)
	data.memory.unseen_elapsed[row] = elapsed
	if visible:
		data.memory.last_seen_position[row] = position
		data.memory.last_seen_velocity[row] = velocity

func perceive(animal: AnimalEntity, delta: float) -> void:
	var memory_perception_ready := data.memory.perception_ready
	var memory_perception_remaining := data.memory.perception_remaining
	var row := animal.row
	data.motion.wander_remaining[row] -= delta
	memory_perception_remaining[row] -= delta
	if not memory_perception_ready[row] or memory_perception_remaining[row] <= 0.0:
		var service: GridService = g_gameplayEngine.grid_service
		data.memory.nearby[row] = service.get_nearby_indices(data.motion.position[row], g_gameplayEngine.config.separation_distance, data.identity.kind[row])
		var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
		_scan_separation(animal, service)
		if g_gameplayEngine.profile_service.detailed_stats_enabled:
			g_gameplayEngine.profile_service.record_hotspot("Separation", started)
		memory_perception_remaining[row] = g_gameplayEngine.config.perception_interval
		if not memory_perception_ready[row]:
			memory_perception_remaining[row] *= fmod(data.identity.entity_id[row] * 0.618034, 1.0)
		memory_perception_ready[row] = 1

func _scan_separation(animal: AnimalEntity, service: GridService) -> void:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	var row := animal.row
	data.motion.separation[row] = Vector2.ZERO
	var distance_limit: float = g_gameplayEngine.config.separation_distance
	if distance_limit <= 0.0:
		return

	var position := data.motion.position[row]
	var kind := data.identity.kind[row]
	var entity_id := data.identity.entity_id[row]
	var positions := spatial.current.cells.positions
	var kinds := spatial.current.cells.kinds
	var separation := Vector2.ZERO
	for index in data.memory.nearby[row]:
		if index == row or kinds[index] != kind:
			continue

		var offset := position - positions[index]
		var distance_squared := offset.length_squared()
		if distance_squared >= distance_limit * distance_limit:
			continue

		var distance := sqrt(distance_squared)
		var direction := offset.normalized()
		if distance < 0.001:
			direction = Vector2.RIGHT if entity_id < data.identity.entity_id[index] else Vector2.LEFT
		separation += direction * (1.0 - distance / distance_limit)

	data.motion.separation[row] = separation

func decide(animal: AnimalEntity, delta: float) -> void:
	if data.identity.kind[animal.row] == AnimalEntity.Kind.SHEEP:
		return

	var row := animal.row
	var settings: Resource = data.settings[row]
	data.motion.intent[row] = AnimalData.MotionIntent.STOP
	data.motion.desired_velocity[row] = Vector2.ZERO
	data.motion.speed_limit[row] = settings.move_speed
	var profile: ProfileService = g_gameplayEngine.profile_service
	var started_at := Time.get_ticks_usec() if profile.performance_stats_enabled else 0
	data.brain.instance[row].update(delta)
	if profile.performance_stats_enabled:
		profile.record_duration("Brain/Update", (Time.get_ticks_usec() - started_at) / 1000.0)

func get_wander_point(animal: AnimalEntity, distance: float) -> Vector2:
	var animal_motion := data.motion
	var motion_wander_point := animal_motion.wander_point
	var row := animal.row
	if animal_motion.wander_remaining[row] <= 0.0 or animal_motion.position[row].distance_to(motion_wander_point[row]) < 15.0:
		var direction := Vector2.from_angle(g_gameplayEngine.rng.randf_range(-PI, PI))
		motion_wander_point[row] = clamp_to_arena(animal, animal_motion.position[row] + direction * distance)
		animal_motion.wander_remaining[row] = g_gameplayEngine.rng.randf_range(1.5, 3.5)
	return motion_wander_point[row]

func clamp_to_arena(animal: AnimalEntity, point: Vector2) -> Vector2:
	return point.clamp(Vector2(12.0, 94.0), g_gameplayEngine.config.arena_size - Vector2(12.0, 58.0))

func move_towards(animal: AnimalEntity, point: Vector2, speed: float, _delta: float) -> void:
	var row := animal.row
	data.motion.intent[row] = AnimalData.MotionIntent.POINT
	data.motion.movement_goal[row] = point
	data.motion.speed_limit[row] = speed

func submit_velocity(animal: AnimalEntity, desired: Vector2, speed: float) -> void:
	var row := animal.row
	data.motion.desired_velocity[row] = desired
	data.motion.speed_limit[row] = speed
	data.motion.movement_goal[row] = data.motion.position[row] + data.motion.desired_velocity[row]
