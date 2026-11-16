class_name AnimalSystem
extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func perception_context(delta: float) -> Dictionary:
	return {"delta": delta, "grid": g_gameplayEngine.grid_service.query_context(),
		"distance": g_gameplayEngine.config.separation_distance, "interval": g_gameplayEngine.config.perception_interval,
		"stats": g_gameplayEngine.grid_service.spatial_stats_enabled, "detailed": g_gameplayEngine.profile_service.detailed_stats_enabled}

static func batch_stats(context: Dictionary) -> Dictionary:
	return {"enabled": context.stats, "detailed": context.detailed, "queries": 0, "candidates": 0, "max_candidates": 0,
		"hotspots": {"NearbyQuery": 0.0, "Separation": 0.0, "NeighborScan": 0.0, "WolfTarget": 0.0, "DogAnchor": 0.0},
		"calls": {"NearbyQuery": 0, "Separation": 0, "NeighborScan": 0, "WolfTarget": 0, "DogAnchor": 0}}

func calculate_perception(row: int, context: Dictionary, stats: Dictionary) -> Dictionary:
	var remaining: float = data.memory_perception_remaining[row] - context.delta
	var refresh := not data.memory_perception_ready[row] or remaining <= 0.0
	var nearby := data.memory_nearby[row]
	var separation := data.motion_separation[row]
	if refresh:
		nearby = GridService.query_snapshot(data.motion_position[row], context.distance, data.identity_kind[row], context.grid, stats)
		var started_at := Time.get_ticks_usec() if stats.detailed else 0
		separation = Vector2.ZERO
		var distance_limit: float = context.distance
		var positions: PackedVector2Array = context.grid.positions
		var kinds: PackedInt32Array = context.grid.kinds
		if distance_limit > 0.0:
			for index in nearby:
				if index == row or kinds[index] != data.identity_kind[row]:
					continue
				var offset := data.motion_position[row] - positions[index]
				var squared := offset.length_squared()
				if squared >= distance_limit * distance_limit:
					continue
				var distance := sqrt(squared)
				var direction := offset.normalized()
				if distance < 0.001:
					direction = Vector2.RIGHT if data.identity_entity_id[row] < data.identity_entity_id[index] else Vector2.LEFT
				separation += direction * (1.0 - distance / distance_limit)
		if stats.detailed:
			stats.hotspots.Separation += (Time.get_ticks_usec() - started_at) / 1000.0
			stats.calls.Separation += 1
		remaining = context.interval
		if not data.memory_perception_ready[row]:
			remaining *= fmod(data.identity_entity_id[row] * 0.618034, 1.0)
	return {"row": row, "remaining": remaining, "refresh": refresh, "nearby": nearby, "separation": separation}

func submit_perception(result: Dictionary, delta: float, advance_wander: bool = true) -> void:
	var row: int = result.row
	if advance_wander:
		data.motion_wander_remaining[row] -= delta
	data.memory_perception_remaining[row] = result.remaining
	data.memory_perception_ready[row] = 1
	if result.refresh:
		data.memory_nearby[row] = result.nearby
		data.motion_separation[row] = result.separation

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
	var lower := Vector2(12.0, 94.0)
	var upper: Vector2 = g_gameplayEngine.config.arena_size - Vector2(12.0, 58.0)
	for row in range(data.active_count):
		var previous := data.motion_position[row]
		var separation := Vector2.ZERO
		if data.identity_kind[row] != AnimalEntity.Kind.SHEEP:
			separation = data.motion_separation[row] * data.settings[row].move_speed
		var velocity := (data.motion_desired_velocity[row] + separation).limit_length(data.motion_speed_limit[row])
		var position := (previous + velocity * delta).clamp(lower, upper)
		velocity = (position - previous) / maxf(delta, 0.00001)
		data.motion_position[row] = position
		data.motion_velocity[row] = velocity
		if not velocity.is_zero_approx():
			data.motion_facing[row] = velocity.normalized()

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

func calculate_observation(row: int, delta: float) -> Dictionary:
	var target := data.live(data.memory_target[row])
	if target == null:
		return {"visible": 0, "elapsed": 0.0}
	var visible := can_see(data.handles[row], data.motion_position[target.row])
	return {"visible": int(visible), "elapsed": 0.0 if visible else data.memory_unseen_elapsed[row] + delta,
		"position": data.motion_position[target.row], "velocity": data.motion_velocity[target.row]}

func submit_observation(row: int, result: Dictionary) -> void:
	data.memory_target_visible[row] = result.visible
	data.memory_unseen_elapsed[row] = result.elapsed
	if result.visible:
		data.memory_last_seen_position[row] = result.position
		data.memory_last_seen_velocity[row] = result.velocity

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
	data.brain_player[row].update(delta)

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
